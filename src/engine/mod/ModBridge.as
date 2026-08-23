package engine.mod
{
   import engine.core.logging.ILogger;
   import flash.desktop.NativeApplication;
   import flash.desktop.NativeProcess;
   import flash.desktop.NativeProcessStartupInfo;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.NativeProcessExitEvent;
   import flash.events.ProgressEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileStream;
   import flash.filesystem.FileMode;
   import flash.utils.ByteArray;
   import flash.utils.getTimer;

   /**
    * ModBridge — NEW FILE (not in original decompile).
    *
    * Bidirectional event bus between the AS3 client and an external mod-host
    * process launched via NativeProcess (requires the extendedDesktop profile,
    * which application.xml already declares).
    *
    * WIRE PROTOCOL (both directions): one JSON object per LF-terminated line.
    *   AS3 -> host (stdin):  {"event":"HTTP_RESPONSE","txn":"AuthTxn","url":"services/auth/login/8","status":200,"success":true,"body":{...}}
    *                         {"event":"RESULT","id":7,"result":"pong"}   (reply to a host command carrying an "id")
    *                         {"event":"ERROR","id":7,"message":"..."}
    *                         generic emits wrap their payload: {"event":"NAME","data":{...}}
    *   host -> AS3 (stdout): {"cmd":"set_spectator","value":true}
    *                         {"cmd":"ping","id":7}
    *   host logging MUST go to stderr — stdout is reserved for protocol lines.
    *   The host MUST exit when stdin reaches EOF — AIR cannot reliably kill it.
    *
    * HOST DISCOVERY: <applicationDirectory>/mods/host.json when present —
    * {"program":"node.exe","args":["host.js"]}, program taken relative to mods/
    * unless absolute — otherwise <applicationDirectory>/mods/host.exe with no
    * arguments. Either way the working directory is mods/, and the resolved
    * program plus arguments are logged on every start. The host runtime
    * (Node, LuaJIT, Python — undecided) is opaque to this class.
    *
    * REDACTION: values of SECRET_FIELDS are stripped from every line in both
    * directions, matched by field name rather than by transaction so a hook site
    * added later cannot forget to opt in. Fails closed on a body that names a
    * secret but will not parse.
    *
    * FAILURE MODE: if NativeProcess is unsupported or host.exe is absent, the
    * bridge marks itself failed once and every emit becomes a cheap no-op.
    * The game must never depend on the host being present.
    */
   public class ModBridge
   {

      private static const HOST_RELPATH:String = "mods/host.exe";

      /**
       * Optional launch descriptor: {"program":"node.exe","args":["host.js"]}.
       * Without it the bridge can only start mods/host.exe with no arguments,
       * which no script-based host can satisfy. `program` is taken relative to
       * mods/ unless it is an absolute path.
       *
       * TRUST: this file names something the game will execute. It is exactly as
       * trusted as an executable dropped in the same folder — no more, but no
       * less, and less obvious. The resolved program and arguments are therefore
       * logged on every start.
       */
      private static const HOST_CONFIG_RELPATH:String = "mods/host.json";

      private static const MAX_RESTARTS:int = 3;

      /** Field names whose VALUES must never reach the host. Matched by name on
       *  every message in both directions, not by transaction — a hook site
       *  added later cannot forget to opt in, and a route that starts echoing a
       *  session key is covered the day it does. `password` and
       *  `steam_auth_ticket` ride out in the login request; `session_key` and
       *  `steamCredentials` come back in its reply. */
      private static const SECRET_FIELDS:Array = ["password","steam_auth_ticket","session_key","steamCredentials"];

      private static const REDACTED:String = "[redacted]";

      /** Depth cap for the redaction walk — bodies are wire JSON, not cyclic
       *  object graphs, but a cap keeps a malformed one from spinning. */
      private static const REDACT_MAX_DEPTH:int = 6;

      /** Hard cap on the accumulated stdout buffer. A host that writes a huge
       *  line with no newline would otherwise grow this without limit. 1 MB is
       *  far above any real command line. */
      private static const MAX_STDOUT_BUF:int = 1048576;

      /** A host that stays up this long counts as a clean run, so the restart
       *  budget resets. Without this, three brief crashes spread over hours
       *  retire the bridge for the rest of the session. */
      private static const CLEAN_RUN_MS:int = 60000;

      private static var s_instance:ModBridge;

      private static var s_failed:Boolean = false;

      /** Set by the host via {"cmd":"set_spectator","value":true}. Future
       *  input-gating injections (e.g. BattleTxn*Send) consult this flag. */
      public static var spectatorMode:Boolean = false;

      private var m_logger:ILogger;

      private var m_proc:NativeProcess;

      private var m_stdoutBuf:ByteArray = new ByteArray();

      private static var s_commands:Object = createBuiltins();

      private var m_restarts:int = 0;

      /** When the current host process started, for the clean-run reset. */
      private var m_startedAt:int = 0;

      private var m_shuttingDown:Boolean = false;

      public function ModBridge(logger:ILogger)
      {
         super();
         m_logger = logger;
      }

      // ---------------------------------------------------------------------
      // Static API — all callers go through these; every path is a no-op when
      // the bridge is failed/absent so hook sites stay one-liners.
      // ---------------------------------------------------------------------

      /** Idempotent. Cheap after first call. Safe to call from hot paths. */
      public static function ensureStarted(logger:ILogger) : void
      {
         if(s_instance || s_failed)
         {
            return;
         }
         if(!NativeProcess.isSupported)
         {
            s_failed = true;
            if(logger)
            {
               logger.info("ModBridge disabled: NativeProcess not supported");
            }
            return;
         }
         var host:Object = resolveHost(logger);
         if(host == null)
         {
            s_failed = true;
            return;
         }
         s_instance = new ModBridge(logger);
         if(!s_instance.start(host))
         {
            s_instance = null;
            s_failed = true;
         }
      }

      /**
       * Work out what to launch. Prefers mods/host.json when present, otherwise
       * falls back to the original mods/host.exe with no arguments. Returns null
       * — meaning "no host, go quiet" — for every failure, so a missing, empty or
       * malformed descriptor behaves exactly like having no host at all and the
       * game runs completely normally.
       *
       * Re-read on every restart, so editing the descriptor takes effect without
       * restarting the game.
       */
      private static function resolveHost(logger:ILogger) : Object
      {
         var modsDir:File = File.applicationDirectory.resolvePath("mods");
         var cfgFile:File = File.applicationDirectory.resolvePath(HOST_CONFIG_RELPATH);
         var args:Vector.<String> = new Vector.<String>();
         var program:File = null;
         if(cfgFile.exists)
         {
            try
            {
               var stream:FileStream = new FileStream();
               stream.open(cfgFile,FileMode.READ);
               var text:String = stream.readUTFBytes(stream.bytesAvailable);
               stream.close();
               var cfg:Object = JSON.parse(text);
               var progName:String = cfg == null ? null : cfg.program as String;
               if(!progName)
               {
                  throw new Error("no \"program\" field");
               }
               program = resolveProgram(modsDir,progName);
               if(cfg.args is Array)
               {
                  for each(var arg:Object in cfg.args as Array)
                  {
                     args.push(String(arg));
                  }
               }
            }
            catch(e:Error)
            {
               if(logger)
               {
                  logger.info("ModBridge disabled: " + HOST_CONFIG_RELPATH + " is unusable (" + e.message + ")");
               }
               return null;
            }
         }
         else
         {
            program = File.applicationDirectory.resolvePath(HOST_RELPATH);
         }
         if(program == null || !program.exists)
         {
            if(logger)
            {
               logger.info("ModBridge disabled: no " + (cfgFile.exists ? "program named by " + HOST_CONFIG_RELPATH : HOST_RELPATH));
            }
            return null;
         }
         return {
            "file":program,
            "args":args,
            "dir":modsDir
         };
      }

      /** An absolute path is used as given (an interpreter usually lives outside
       *  the game folder); anything else is taken relative to mods/. */
      private static function resolveProgram(modsDir:File, progName:String) : File
      {
         var absolute:File = null;
         if(/^([a-zA-Z]:[\\\/]|\\\\|\/)/.test(progName))
         {
            absolute = new File();
            absolute.nativePath = progName;
            return absolute;
         }
         return modsDir.resolvePath(progName);
      }

      public static function get running() : Boolean
      {
         return s_instance != null && s_instance.m_proc != null && s_instance.m_proc.running;
      }

      /** General event emit. `data` must be JSON-stringify-safe; throws are swallowed. */
      public static function emit(eventName:String, data:Object = null) : void
      {
         if(!running)
         {
            return;
         }
         try
         {
            s_instance.writeLine(redactJsonText(JSON.stringify({
               "event":eventName,
               "data":data
            })));
         }
         catch(e:Error)
         {
            s_instance.logInfo("ModBridge emit(" + eventName + ") failed: " + e.message);
         }
      }

      /**
       * HTTP response emit. `rawBody` is the verbatim wire string — spliced into
       * the envelope WITHOUT re-stringify when it is single-line JSON, so the
       * host sees exactly what the server sent. Multi-line or non-JSON bodies
       * are wrapped as a JSON string (the line protocol forbids embedded LF).
       */
      public static function emitHttpResponse(txn:String, url:String, status:int, ok:Boolean, rawBody:String) : void
      {
         if(!running)
         {
            return;
         }
         try
         {
            var head:String = JSON.stringify({
               "event":"HTTP_RESPONSE",
               "txn":txn,
               "url":url,
               "status":status,
               "success":ok
            });
            s_instance.writeLine(spliceBody(head,redactJsonText(rawBody)));
         }
         catch(e:Error)
         {
            s_instance.logInfo("ModBridge emitHttpResponse failed: " + e.message);
         }
      }

      /** Outbound request emit — the player's own actions (e.g. BattleTxnMoveSend
       *  move data) travel in requests, not responses, so replays/combat logs need this. */
      public static function emitHttpRequest(txn:String, url:String, body:Object) : void
      {
         if(!running)
         {
            return;
         }
         try
         {
            var envelope:Object = {
               "event":"HTTP_REQUEST",
               "txn":txn,
               "url":url
            };
            var rawBody:String = null;
            if(body is String)
            {
               // Already-stringified JSON (e.g. LobbyOptionsTxn) — splice verbatim.
               rawBody = String(body);
            }
            else if(body is ByteArray)
            {
               // Binary body (IAP path) — flag it rather than emit reflection junk.
               envelope.bodyType = "binary";
            }
            else if(body != null)
            {
               rawBody = JSON.stringify(body);
            }
            s_instance.writeLine(spliceBody(JSON.stringify(envelope),redactJsonText(rawBody)));
         }
         catch(e:Error)
         {
            s_instance.logInfo("ModBridge emitHttpRequest failed: " + e.message);
         }
      }

      /**
       * Expose a named command to mods. Replaces raw reflection: hook sites (or
       * future injections) register explicit, typed entry points.
       *   ModBridge.registerCommand("get_roster", function(args:Object):Object { ... return data; });
       * A non-null return is sent back when the command carried an "id".
       * The registry is static: registrations made before the bridge starts
       * (or when no host is present) are kept, never dropped.
       */
      public static function registerCommand(name:String, handler:Function) : void
      {
         s_commands[name] = handler;
      }

      // ---------------------------------------------------------------------
      // Instance internals
      // ---------------------------------------------------------------------

      private function start(host:Object) : Boolean
      {
         var hostExe:File = host.file as File;
         var hostArgs:Vector.<String> = host.args as Vector.<String>;
         try
         {
            var info:NativeProcessStartupInfo = new NativeProcessStartupInfo();
            info.executable = hostExe;
            info.workingDirectory = host.dir as File;
            info.arguments = hostArgs;
            m_proc = new NativeProcess();
            m_proc.addEventListener("standardOutputData",onStdout);
            m_proc.addEventListener("standardErrorData",onStderr);
            m_proc.addEventListener("exit",onExit);
            m_proc.addEventListener("standardInputIoError",onStdinError);
            m_proc.start(info);
            m_startedAt = getTimer();
            NativeApplication.nativeApplication.addEventListener("exiting",onAppExiting);
            // Always say exactly what was launched — mods/host.json can point this
            // at anything, and a silent launch would hide that.
            logInfo("ModBridge started host: " + hostExe.nativePath + (hostArgs.length > 0 ? " " + hostArgs.join(" ") : ""));
            emit("BRIDGE_READY",null);
            return true;
         }
         catch(e:Error)
         {
            logInfo("ModBridge failed to start host: " + e.message);
         }
         return false;
      }

      private function writeLine(line:String) : void
      {
         // Single write; line must not contain LF (callers guarantee via spliceBody).
         m_proc.standardInput.writeUTFBytes(line + "\n");
      }

      /**
       * Cheap pre-check: does this text mention any secret field at all? The tap
       * is a firehose, and parsing every body would be wasteful when almost none
       * carry a secret. A substring scan costs far less than a JSON parse, so
       * only a hit pays for one.
       */
      private static function containsSecret(text:String) : Boolean
      {
         if(text == null)
         {
            return false;
         }
         for each(var field:String in SECRET_FIELDS)
         {
            if(text.indexOf(field) >= 0)
            {
               return true;
            }
         }
         return false;
      }

      /**
       * Replace the value of every secret field with a marker, anywhere in a
       * JSON body. Works on the TEXT rather than on the live object, so it can
       * never mutate the body the game is about to send, and so JSON.parse hands
       * back plain dynamic objects that `for...in` walks correctly (a typed
       * instance like ClientConfigData would enumerate as empty).
       *
       * FAILS CLOSED: if the text mentions a secret but will not parse, the whole
       * body is replaced rather than passed through. Losing a line the host wanted
       * beats leaking a password on a body we could not read.
       */
      private static function redactJsonText(rawBody:String) : String
      {
         if(!containsSecret(rawBody))
         {
            return rawBody;
         }
         try
         {
            var parsed:Object = JSON.parse(rawBody);
            var scrubbed:Object = redactValue(parsed,0);
            return JSON.stringify(scrubbed);
         }
         catch(e:Error)
         {
         }
         return JSON.stringify(REDACTED + " (unparseable body naming a secret field)");
      }

      /** Recursive walk of parsed JSON, returning a copy with secret values
       *  replaced. Depth-capped; anything past the cap is dropped rather than
       *  passed through, so the cap can never become a way out. */
      private static function redactValue(value:Object, depth:int) : Object
      {
         if(value == null || !(value is Object) || value is String || value is Number || value is Boolean)
         {
            return value;
         }
         if(depth >= REDACT_MAX_DEPTH)
         {
            return REDACTED + " (nested too deeply to check)";
         }
         var i:int = 0;
         var out:Object = null;
         if(value is Array)
         {
            out = [];
            var arr:Array = value as Array;
            while(i < arr.length)
            {
               out[i] = redactValue(arr[i],depth + 1);
               i++;
            }
            return out;
         }
         out = {};
         for(var key:String in value)
         {
            out[key] = SECRET_FIELDS.indexOf(key) >= 0 ? REDACTED : redactValue(value[key],depth + 1);
         }
         return out;
      }

      /**
       * Append `rawBody` as a "body" field on an already-stringified envelope.
       * Splices verbatim only when it looks like single-line JSON; otherwise
       * re-encodes as a JSON string so the one-line-per-message framing holds.
       * NOTE: a malformed single-line body that starts with { or [ corrupts only
       * its own line — the host must try/catch per line and report PARSE_ERROR.
       */
      private static function spliceBody(head:String, rawBody:String) : String
      {
         var bodyJson:String = "null";
         if(rawBody != null)
         {
            var c:String = rawBody.charAt(0);
            if((c == "{" || c == "[") && rawBody.indexOf("\n") < 0 && rawBody.indexOf("\r") < 0)
            {
               bodyJson = rawBody;
            }
            else
            {
               bodyJson = JSON.stringify(rawBody);
            }
         }
         return head.substring(0,head.length - 1) + ",\"body\":" + bodyJson + "}";
      }

      /**
       * stdout arrives in arbitrary chunks: a line may span multiple
       * ProgressEvents, and multi-byte UTF-8 sequences may split across chunk
       * boundaries. Accumulate bytes; only decode up to the last LF (LF is a
       * single byte in UTF-8, so complete lines are always whole sequences).
       */
      private function onStdout(event:ProgressEvent) : void
      {
         drainStdout();
      }

      /** Split out from the event handler so shutdown can call it too — see
       *  onAppExiting, which drains once before the force-kill. */
      private function drainStdout() : void
      {
         var avail:uint = m_proc.standardOutput.bytesAvailable;
         if(avail == 0)
         {
            return;
         }
         m_proc.standardOutput.readBytes(m_stdoutBuf,m_stdoutBuf.length,avail);
         var lastNL:int = -1;
         var i:int = m_stdoutBuf.length - 1;
         while(i >= 0)
         {
            if(m_stdoutBuf[i] == 10)
            {
               lastNL = i;
               break;
            }
            i--;
         }
         if(lastNL < 0)
         {
            // No complete line yet. Normally we just wait for more, but a host
            // that writes without ever ending a line would grow this forever.
            if(m_stdoutBuf.length > MAX_STDOUT_BUF)
            {
               logInfo("ModBridge dropped " + m_stdoutBuf.length + " buffered bytes: host wrote more than " + MAX_STDOUT_BUF + " bytes with no line break");
               m_stdoutBuf = new ByteArray();
            }
            return;
         }
         m_stdoutBuf.position = 0;
         var chunk:String = m_stdoutBuf.readUTFBytes(lastNL + 1);
         var rest:ByteArray = new ByteArray();
         if(m_stdoutBuf.bytesAvailable > 0)
         {
            m_stdoutBuf.readBytes(rest);
         }
         m_stdoutBuf = rest;
         var lines:Array = chunk.split("\n");
         for each(var line:String in lines)
         {
            if(line.length > 0 && line.charCodeAt(line.length - 1) == 13)
            {
               line = line.substring(0,line.length - 1);
            }
            if(line.length == 0)
            {
               continue;
            }
            processLine(line);
         }
      }

      private function onStderr(event:ProgressEvent) : void
      {
         try
         {
            var msg:String = m_proc.standardError.readUTFBytes(m_proc.standardError.bytesAvailable);
            logInfo("[modhost] " + msg.replace(/\s+$/,""));
         }
         catch(e:Error)
         {
         }
      }

      private function processLine(line:String) : void
      {
         var cmd:Object = null;
         try
         {
            cmd = JSON.parse(line);
         }
         catch(e:Error)
         {
            logInfo("ModBridge dropped malformed line: " + line.substring(0,200));
            return;
         }
         try
         {
            executeCommand(cmd);
         }
         catch(e2:Error)
         {
            logInfo("ModBridge command failed: " + e2.message);
            if(cmd && cmd.hasOwnProperty("id"))
            {
               sendReply({
                  "event":"ERROR",
                  "id":cmd.id,
                  "message":e2.message
               });
            }
         }
      }

      private function executeCommand(cmd:Object) : void
      {
         var name:String = cmd.cmd as String;
         if(!name)
         {
            return;
         }
         var handler:Function = s_commands[name] as Function;
         if(handler == null)
         {
            if(cmd.hasOwnProperty("id"))
            {
               sendReply({
                  "event":"ERROR",
                  "id":cmd.id,
                  "message":"unknown command: " + name
               });
            }
            return;
         }
         var result:Object = handler(cmd);
         if(cmd.hasOwnProperty("id"))
         {
            sendReply({
               "event":"RESULT",
               "id":cmd.id,
               "result":result
            });
         }
      }

      /** Replies use the flat documented shape — NOT the emit() data envelope. */
      private function sendReply(reply:Object) : void
      {
         try
         {
            writeLine(JSON.stringify(reply));
         }
         catch(e:Error)
         {
            logInfo("ModBridge sendReply failed: " + e.message);
         }
      }

      private static function createBuiltins() : Object
      {
         var cmds:Object = {};
         cmds["ping"] = function(cmd:Object):Object
         {
            return "pong";
         };
         cmds["set_spectator"] = function(cmd:Object):Object
         {
            spectatorMode = cmd.value == true;
            return spectatorMode;
         };
         return cmds;
      }

      private function onExit(event:NativeProcessExitEvent) : void
      {
         logInfo("ModBridge host exited, code=" + event.exitCode);
         // A host that stayed up counts as a clean run, so the restart budget
         // starts over. Otherwise three unrelated blips hours apart would retire
         // the bridge for the rest of the session.
         if(m_startedAt != 0 && getTimer() - m_startedAt >= CLEAN_RUN_MS && m_restarts > 0)
         {
            logInfo("ModBridge host ran cleanly for " + (getTimer() - m_startedAt) + "ms; restart count reset");
            m_restarts = 0;
         }
         cleanupProcess();
         if(m_shuttingDown)
         {
            return;
         }
         if(m_restarts < MAX_RESTARTS)
         {
            m_restarts++;
            logInfo("ModBridge restarting host (attempt " + m_restarts + "/" + MAX_RESTARTS + ")");
            // Re-resolve rather than reuse: a descriptor edited while the game is
            // running takes effect on the next restart.
            var host:Object = resolveHost(m_logger);
            if(host == null || !start(host))
            {
               s_failed = true;
            }
         }
         else
         {
            logInfo("ModBridge giving up after " + MAX_RESTARTS + " restarts");
            s_failed = true;
         }
      }

      private function onStdinError(event:IOErrorEvent) : void
      {
         logInfo("ModBridge stdin error: " + event.text);
      }

      private function onAppExiting(event:Event) : void
      {
         m_shuttingDown = true;
         if(m_proc && m_proc.running)
         {
            try
            {
               emit("SHUTDOWN",null);
               m_proc.closeInput();
               // Take whatever the host has already written but we have not read
               // yet. Without this the force-kill below discards its last lines,
               // which is exactly where a summary or a final result would be.
               drainStdout();
            }
            catch(e:Error)
            {
            }
            // closeInput() delivers EOF (host contract: exit on EOF), then
            // force-kill so a misbehaving host can't outlive the game as an
            // orphan. Hosts must not rely on time between SHUTDOWN and kill.
            m_proc.exit(true);
         }
      }

      private function cleanupProcess() : void
      {
         if(m_proc)
         {
            m_proc.removeEventListener("standardOutputData",onStdout);
            m_proc.removeEventListener("standardErrorData",onStderr);
            m_proc.removeEventListener("exit",onExit);
            m_proc.removeEventListener("standardInputIoError",onStdinError);
            m_proc = null;
         }
         m_stdoutBuf = new ByteArray();
      }

      private function logInfo(msg:String) : void
      {
         if(m_logger)
         {
            m_logger.info(msg);
         }
      }
   }
}
