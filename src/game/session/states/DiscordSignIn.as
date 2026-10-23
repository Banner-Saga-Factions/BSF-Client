package game.session.states
{
   import engine.core.fsm.StateData;
   import engine.core.http.HttpCommunicator;
   import engine.core.logging.ILogger;
   import engine.session.Credentials;
   import flash.events.TimerEvent;
   import flash.net.URLRequest;
   import flash.net.navigateToURL;
   import flash.utils.Timer;
   import game.cfg.GameConfig;
   import game.gui.IGuiDialog;
   import game.session.actions.DiscordHandoffTxn;
   import game.session.actions.DiscordPollTxn;

   /**
    * BSF patch (#2): signing in through Discord when Steam cannot be used. One hand-off from
    * start to finish:
    *
    *   1. ask the server for a hand-off (a short code to show, a secret key to keep);
    *   2. open the server's page in the browser and show the code, with Retry / Cancel;
    *   3. ask the server "done yet?" every two seconds;
    *   4. when it says ready, hand the key to the ordinary sign-in as its password.
    *
    * Anything that ends the hand-off without signing in goes to the game's own "Login Failed"
    * dialog (AuthFailedState), whose Retry is the only thing that starts a new hand-off — this
    * class never starts one by itself, which would open the browser again unasked.
    *
    * What the server expects: bsf-server/docs/client-contract.md, "Signing in through Discord".
    * The key is never written to the log.
    */
   public class DiscordSignIn
   {

      /** Set by AuthState when the server refuses a Steam sign-in, so the next PreAuthState
       *  goes straight to Discord instead of sending the refused Steam proof again. */
      public static var steamRefused:Boolean = false;

      /** A sign-in password starting with this carries a hand-off key (server: auth.ts). */
      public static const PASSWORD_PREFIX:String = "discord:";

      private static const POLL_MS:int = 2000;

      /** The server allows 300 polls a minute from one address; past that it answers 429. */
      private static const RATE_LIMITED_MS:int = 60000;

      private static const RETRY:String = "Retry";

      private static const CANCEL:String = "Cancel";

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
         if(handoffTxn)
         {
            handoffTxn.abort();
            handoffTxn = null;
         }
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
         key = txn.key;
         code = txn.code;
         pageUrl = txn.pageUrl;
         logger.info("DiscordSignIn hand-off " + code + " started; opening " + pageUrl);
         openBrowser();
         showDialog();
         schedulePoll(POLL_MS);
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
         dialog.openTwoBtnDialog("Sign in with Discord","Your code: <font color=\'#ffdd00\'>" + code + "</font>\n\n" + "A Discord sign-in page has opened in your browser. It may be behind the game.\n" + "Check it shows the same code, press Continue, then Authorize.\n\n" + "Retry opens the page again.",RETRY,CANCEL,dialogHandler);
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
            fail("Discord sign-in was cancelled.");
            return;
         }
         logger.info("DiscordSignIn Retry: opening the page again");
         openBrowser();
         showDialog();
      }
   }
}
