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
   import flash.utils.ByteArray;

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
    * HOST DISCOVERY: <applicationDirectory>/mods/host.exe, launched with the
    * mods/ directory as working directory and no arguments. The host runtime
    * (Node, LuaJIT, Python — undecided) is opaque to this class.
    *
    * FAILURE MODE: if NativeProcess is unsupported or host.exe is absent, the
    * bridge marks itself failed once and every emit becomes a cheap no-op.
    * The game must never depend on the host being present.
    */
   public class ModBridge
   {

      private static const HOST_RELPATH:String = "mods/host.exe";

      private static const MAX_RESTARTS:int = 3;

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
         var hostExe:File = File.applicationDirectory.resolvePath(HOST_RELPATH);
         if(!hostExe.exists)
         {
            s_failed = true;
            if(logger)
            {
               logger.info("ModBridge disabled: no " + HOST_RELPATH);
            }
            return;
         }
         s_instance = new ModBridge(logger);
         if(!s_instance.start(hostExe))
         {
            s_instance = null;
            s_failed = true;
         }
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
            s_instance.writeLine(JSON.stringify({
               "event":eventName,
               "data":data
            }));
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
            s_instance.writeLine(spliceBody(head,rawBody));
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
            s_instance.writeLine(spliceBody(JSON.stringify(envelope),rawBody));
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

      private function start(hostExe:File) : Boolean
      {
         try
         {
            var info:NativeProcessStartupInfo = new NativeProcessStartupInfo();
            info.executable = hostExe;
            info.workingDirectory = hostExe.parent;
            m_proc = new NativeProcess();
            m_proc.addEventListener("standardOutputData",onStdout);
            m_proc.addEventListener("standardErrorData",onStderr);
            m_proc.addEventListener("exit",onExit);
            m_proc.addEventListener("standardInputIoError",onStdinError);
            m_proc.start(info);
            NativeApplication.nativeApplication.addEventListener("exiting",onAppExiting);
            logInfo("ModBridge started host: " + hostExe.nativePath);
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
         cleanupProcess();
         if(m_shuttingDown)
         {
            return;
         }
         if(m_restarts < MAX_RESTARTS)
         {
            m_restarts++;
            logInfo("ModBridge restarting host (attempt " + m_restarts + "/" + MAX_RESTARTS + ")");
            var hostExe:File = File.applicationDirectory.resolvePath(HOST_RELPATH);
            if(!hostExe.exists || !start(hostExe))
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
