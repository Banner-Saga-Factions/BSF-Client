package game.session.states
{
   import engine.core.fsm.StateData;
   import engine.core.http.HttpCommunicator;
   import engine.core.logging.ILogger;
   import engine.session.Credentials;
   import flash.display.DisplayObject;
   import flash.events.TimerEvent;
   import flash.net.URLRequest;
   import flash.net.navigateToURL;
   import flash.utils.Timer;
   import game.cfg.GameConfig;
   import game.gui.IGuiDialog;
   import game.session.actions.DiscordHandoffTxn;
   import game.session.actions.DiscordPollTxn;

   /**
    * BSF patch (#2, #96): signing in through Discord, when the player chose it — in the
    * "Couldn't sign in with Steam" question, at an earlier launch (the saved choice), or with
    * --steam false. PreAuthState decides; the game never picks Discord by itself. One hand-off
    * from start to finish:
    *
    *   1. ask the server for a hand-off (a short code to show, a secret key to keep);
    *   2. open the server's page in the browser and show the code, with Retry / Cancel;
    *   3. ask the server "done yet?" every two seconds;
    *   4. when it says ready, hand the key to the ordinary sign-in as its password.
    *
    * Anything that ends the hand-off without signing in goes to the game's own "Login Failed"
    * dialog (AuthFailedState), whose Retry starts a new hand-off. This class never starts one by
    * itself, which would open the browser again unasked. One exception asks first: Cancel when
    * Discord is the saved choice offers [Try Discord again] [Use Steam next time] instead.
    *
    * What the server expects: bsf-server/docs/client-contract.md, "Signing in through Discord".
    * The key is never written to the log.
    */
   public class DiscordSignIn
   {

      /** Set by AuthState when the server refuses a Steam sign-in, so the next PreAuthState
       *  asks the player instead of sending the refused Steam proof again. */
      public static var steamRefused:Boolean = false;

      /** Set by AuthState when the server could not check a Steam sign-in just now (409,
       *  BSF-Custom-Server #391). Like steamRefused, but a passing fault: choosing Discord after
       *  it is not remembered. */
      public static var steamUnchecked:Boolean = false;

      /** Set by StartState when the game was started with --steam false. */
      public static var steamTurnedOff:Boolean = false;

      /** True once Discord is this run's way in, so every later sign-in in the run (Login
       *  Failed's Retry, a dropped connection) goes to Discord without asking again. */
      public static var discordThisRun:Boolean = false;

      /** The saved way to sign in (#96), in the game's own settings file: ROUTE_DISCORD skips
       *  Steam at launch; anything else, or nothing, tries Steam first. */
      public static const PREF_SIGNIN_ROUTE:String = "signin_route";

      public static const ROUTE_DISCORD:String = "discord";

      public static const ROUTE_STEAM:String = "steam";

      /** A sign-in password starting with this carries a hand-off key (server: auth.ts). */
      public static const PASSWORD_PREFIX:String = "discord:";

      private static const POLL_MS:int = 2000;

      /** The server allows 300 polls a minute from one address; past that it answers 429. */
      private static const RATE_LIMITED_MS:int = 60000;

      private static const RETRY:String = "Retry";

      private static const CANCEL:String = "Cancel";

      /** The two buttons offered when Discord is the saved choice and its sign-in is cancelled. */
      private static const TRY_AGAIN:String = "Try Discord again";

      private static const USE_STEAM:String = "Use Steam next time";

      /** How much larger than stock the sign-in dialogs are drawn (see enlarge). */
      private static const DIALOG_SCALE:Number = 1.75;

      private var config:GameConfig;

      private var credentials:Credentials;

      private var communicator:HttpCommunicator;

      private var data:StateData;

      private var logger:ILogger;

      private var handoffTxn:DiscordHandoffTxn;

      private var pollTxn:DiscordPollTxn;

      private var timer:Timer;

      private var dialog:IGuiDialog;

      private var key:String;

      private var code:String;

      private var pageUrl:String;

      private var stopped:Boolean;

      public function DiscordSignIn(config:GameConfig, credentials:Credentials, communicator:HttpCommunicator, data:StateData, logger:ILogger)
      {
         super();
         this.config = config;
         this.credentials = credentials;
         this.communicator = communicator;
         this.data = data;
         this.logger = logger;
      }

      public static function isDiscordPassword(password:String) : Boolean
      {
         return password != null && password.indexOf(PASSWORD_PREFIX) == 0;
      }

      public static function savedRouteIsDiscord(config:GameConfig) : Boolean
      {
         return config.globalPrefs != null && config.globalPrefs.getPref(PREF_SIGNIN_ROUTE) == ROUTE_DISCORD;
      }

      /** Saves the way to sign in at the next launch: ROUTE_DISCORD or ROUTE_STEAM. */
      public static function saveRoute(config:GameConfig, route:String, logger:ILogger) : void
      {
         if(!config.globalPrefs)
         {
            return;
         }
         // Steam is saved as a word, not by removing the setting: the game's settings store
         // forgets a removed setting only until the next launch, then reads it back from the
         // file (PrefBag.setPref with null drops it from memory and leaves the file alone).
         config.globalPrefs.setPref(PREF_SIGNIN_ROUTE,route);
         // Written to the file now, not by the store's own one-second timer: the game may be
         // closing straight after, and quitting closes it after half a second
         // (GameMainAir.exitingHandler), before that timer fires.
         try
         {
            config.globalPrefs.savePrefs();
         }
         catch(e:Error)
         {
            // A file that can't be written must not stop the button's own action (signing in,
            // or closing the game); the choice is just not kept.
            logger.error("DiscordSignIn could not save the way to sign in: " + e.message);
         }
      }

      /** Draws a sign-in dialog 1.75 times stock size, the size the owner chose after seeing
       *  it in the game (#96). Call after opening: opening sets the size afresh from the window
       *  (GuiDialog, in an art file this build can't change). The dialog is centred, so it
       *  grows evenly. */
      public static function enlarge(dialog:IGuiDialog) : void
      {
         var clip:DisplayObject = dialog as DisplayObject;
         if(clip)
         {
            clip.scaleX *= DIALOG_SCALE;
            clip.scaleY *= DIALOG_SCALE;
         }
      }

      public function start() : void
      {
         logger.info("DiscordSignIn asking the server for a hand-off");
         handoffTxn = new DiscordHandoffTxn(handoffHandler,logger);
         handoffTxn.send(communicator);
      }

      /** Safe to call more than once; PreAuthState calls it on every way out. */
      public function stop() : void
      {
         stopped = true;
         if(timer)
         {
            timer.removeEventListener(TimerEvent.TIMER_COMPLETE,pollTimerHandler);
            timer.stop();
            timer = null;
         }
         // Forgotten, not cancelled: the game writes a cancelled request's late reply to its debug
         // log, and this reply carries the key. handoffHandler ignores it once stopped.
         handoffTxn = null;
         if(pollTxn)
         {
            pollTxn.abort();
            pollTxn = null;
         }
         closeDialog();
      }

      private function handoffHandler(txn:DiscordHandoffTxn) : void
      {
         if(stopped || txn != handoffTxn)
         {
            return;
         }
         handoffTxn = null;
         if(!txn.success || !txn.key || !txn.pageUrl)
         {
            fail(txn.refusal ? txn.refusal : "Could not reach the server to start Discord sign-in.");
            return;
         }
         // Only a web page is opened. Any other kind of address could start something else on
         // the player's computer, and the address comes from whichever server the game was given.
         if(!isWebAddress(txn.pageUrl))
         {
            fail("The server sent a sign-in page address the game will not open.");
            return;
         }
         key = txn.key;
         code = txn.code;
         pageUrl = txn.pageUrl;
         logger.info("DiscordSignIn hand-off " + code + " started; opening " + pageUrl);
         openBrowser();
         showDialog();
         schedulePoll(POLL_MS);
      }

      private static function isWebAddress(address:String) : Boolean
      {
         var lower:String = address.toLowerCase();
         return lower.indexOf("https://") == 0 || lower.indexOf("http://") == 0;
      }

      private function schedulePoll(delayMs:int) : void
      {
         timer = new Timer(delayMs,1);
         timer.addEventListener(TimerEvent.TIMER_COMPLETE,pollTimerHandler);
         timer.start();
      }

      private function pollTimerHandler(event:TimerEvent) : void
      {
         if(timer)
         {
            timer.removeEventListener(TimerEvent.TIMER_COMPLETE,pollTimerHandler);
            timer = null;
         }
         if(stopped)
         {
            return;
         }
         pollTxn = new DiscordPollTxn(key,pollHandler,logger);
         pollTxn.send(communicator);
      }

      private function pollHandler(txn:DiscordPollTxn) : void
      {
         if(stopped || txn != pollTxn)
         {
            return;
         }
         pollTxn = null;
         if(txn.responseCode == 429)
         {
            logger.info("DiscordSignIn asked too often; waiting a minute");
            schedulePoll(RATE_LIMITED_MS);
            return;
         }
         var status:String = txn.success ? txn.status : null;
         if(status == "pending")
         {
            schedulePoll(POLL_MS);
            return;
         }
         if(status == "ready")
         {
            finish();
            return;
         }
         if(status == "failed" || status == "expired")
         {
            fail(txn.serverMessage ? txn.serverMessage : "Discord sign-in did not finish.");
            return;
         }
         // No answer, or one we do not know: keep asking. The player can still Cancel, and a
         // hand-off left too long comes back "expired" once the server answers again.
         logger.info("DiscordSignIn poll got " + txn.responseCode + "; asking again");
         schedulePoll(POLL_MS);
      }

      private function finish() : void
      {
         var signInKey:String = key;
         stop();
         logger.info("DiscordSignIn hand-off " + code + " is ready; signing in");
         credentials.steamId = null;
         credentials.steamAuthTicket = null;
         credentials.password = PASSWORD_PREFIX + signInKey;
         credentials.vbb_name = "discord";
         // Marks this sign-in as one that must succeed, so a refusal goes straight to "Login
         // Failed" with the server's own words. Without it the stock game swallows the first
         // refusal and asks again later — and the key is used up by then, so the second
         // answer would say "expired" and hide the real reason.
         data.setValue(GameStateDataEnum.AUTH_REQUIRE,true);
         credentials.commit();
      }

      private function fail(reason:String) : void
      {
         stop();
         logger.info("DiscordSignIn stopped: " + reason);
         data.setValue(GameStateDataEnum.SERVER_MESSAGE,reason);
         config.fsm.transitionTo(AuthFailedState,data);
      }

      private function openBrowser() : void
      {
         try
         {
            navigateToURL(new URLRequest(pageUrl),"_blank");
         }
         catch(e:Error)
         {
            logger.error("DiscordSignIn could not open the browser: " + e.message);
         }
      }

      private function showDialog() : void
      {
         closeDialog();
         dialog = config.gameGuiContext.createDialog();
         // Kept short: in the stock dialog a longer body rides up into the title and loses its
         // last line.
         dialog.openTwoBtnDialog("Sign in with Discord","Your code: <font color=\'#ffdd00\'>" + code + "</font>\n" + "In your browser (it may be behind the game), check the code, then press Continue and Authorize. " + "Retry opens the page again.",RETRY,CANCEL,dialogHandler);
         enlarge(dialog);
      }

      private function closeDialog() : void
      {
         if(dialog)
         {
            // Cleared first: closing calls dialogHandler with no button, which must be a no-op.
            var closing:IGuiDialog = dialog;
            dialog = null;
            closing.closeDialog(null);
         }
      }

      private function dialogHandler(button:String) : void
      {
         if(!button || stopped)
         {
            return;
         }
         // A button press has already closed the dialog.
         dialog = null;
         if(button == CANCEL)
         {
            // PATCH begin (#96): when Discord is the saved choice, this is the way back to
            // Steam: without it, a player who chose Discord once would get it at every launch.
            // Not after --steam false, which asked for Discord whatever is saved, nor on the
            // --steam_id test route, which never reads or writes the saved choice.
            if(!steamTurnedOff && !config.options.overrideSteamId && savedRouteIsDiscord(config))
            {
               stop();
               showSavedChoiceDialog();
               return;
            }
            fail("Discord sign-in was cancelled. Retry starts it again; to use Steam, press Disconnect, start Steam, then the game.");
            // PATCH end
            return;
         }
         logger.info("DiscordSignIn Retry: opening the page again");
         openBrowser();
         showDialog();
      }

      // PATCH begin (#96)
      private function showSavedChoiceDialog() : void
      {
         logger.info("DiscordSignIn cancelled with Discord saved; offering the way back to Steam");
         dialog = config.gameGuiContext.createDialog();
         // Kept short, like the code dialog above.
         dialog.openTwoBtnDialog("Discord sign-in cancelled","Discord is your saved way to sign in. Steam and Discord are separate accounts. " + "\"" + USE_STEAM + "\" closes the game; start Steam, then the game.",TRY_AGAIN,USE_STEAM,savedChoiceDialogHandler);
         enlarge(dialog);
      }

      private function savedChoiceDialogHandler(button:String) : void
      {
         // No button: closed by stop(), when PreAuthState is left.
         if(!button || !dialog)
         {
            return;
         }
         dialog = null;
         if(button == USE_STEAM)
         {
            logger.info("DiscordSignIn saving Steam for the next launch, then closing the game");
            saveRoute(config,ROUTE_STEAM,logger);
            // The same way out as the "Login Failed" dialog's Disconnect button (LoginPage).
            config.context.appInfo.terminateError("Discord sign-in cancelled; Steam saved for next launch");
            return;
         }
         // The player asked for it, so a new hand-off may open the browser again.
         logger.info("DiscordSignIn trying again with a new hand-off");
         stopped = false;
         start();
      }
      // PATCH end
   }
}
