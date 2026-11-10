package game.session.states
{
   import engine.core.fsm.Fsm;
   import engine.core.fsm.StateData;
   import engine.core.fsm.StatePhase;
   import engine.core.logging.ILogger;
   import engine.steamworks.NullSteamworks;
   import flash.events.Event;
   import game.gui.IGuiDialog;
   import game.session.GameState;

   public class PreAuthState extends GameState
   {

      // PATCH begin (#96, #97): the "Couldn't sign in with Steam" question and its two buttons,
      // [Sign in with Discord] [Quit]. When the server only couldn't check Steam just now, a
      // passing fault, they are [Try Steam again] [Sign in with Discord] instead (#97).
      private static const USE_DISCORD:String = "Sign in with Discord";

      private static const QUIT:String = "Quit";

      private static const TRY_STEAM:String = "Try Steam again";

      private var steamFailedDialog:IGuiDialog;

      // Whether choosing Discord in the question is saved for later launches. Not when the server
      // only could not check Steam just now, a passing fault: saving it would keep a Steam owner
      // in Discord. Not on the --steam_id test route either, which never reads the saved choice.
      private var steamFailedRemember:Boolean;
      // PATCH end

      // PATCH (#2): the Discord sign-in in progress, when Steam could not be used.
      private var discord:DiscordSignIn;

      public function PreAuthState(param1:StateData, param2:Fsm, param3:ILogger)
      {
         super(param1,param2,param3);
      }

      override protected function handleEnteredState() : void
      {
         if(gameFsm.config.options.alwaysOffline)
         {
            phase = StatePhase.COMPLETED;
            return;
         }
         credentials.addEventListener("Credentials.EVENT_COMMITTED",credentialsChangeEvent);
         gameFsm.logout();
         chooseSignIn();
      }

      // PATCH (#97): the rest of entering this state, on its own so that "Try Steam again" can
      // run it a second time. The retry cannot simply enter this state again: the state machine
      // ignores a move to the state it is already in (Fsm.setCurrentState in the decompile).
      private function chooseSignIn() : void
      {
         // PATCH (#2): true once the --steam_id test route has committed its made-up proof.
         var overrideCommitted:Boolean = false;
         // PATCH begin (#96): Discord without trying Steam, in three cases: Discord is already
         // this run's way in (Login Failed's Retry, a dropped connection), the game was started
         // with --steam false, or the player chose Discord at an earlier launch. The first holds
         // on every route; the --steam_id test route and kiosk mode skip the other two, and the
         // test route never reads the saved choice.
         if(DiscordSignIn.discordThisRun)
         {
            startDiscordSignIn();
            return;
         }
         if(!config.options.overrideSteamId && !config.runMode.autologin)
         {
            if(DiscordSignIn.steamTurnedOff)
            {
               startDiscordSignIn();
               return;
            }
            if(DiscordSignIn.savedRouteIsDiscord(config))
            {
               logger.info("PreAuthState Discord is the saved way to sign in; not trying Steam");
               startDiscordSignIn();
               return;
            }
         }
         // PATCH end
         // PATCH (#2, #96, #97): skip Steam once the server has refused its proof, or could not
         // check it (AuthState sets both), so the same proof is not sent again. "Try Steam again"
         // clears the second, after telling Steam the old proof is no longer needed.
         if(credentials.steamId && !DiscordSignIn.steamRefused && !DiscordSignIn.steamUnchecked)
         {
            credentials.steamAuthTicketHandle = 1;
            credentials.steamAuthTicket = null;
            if(config.options.overrideSteamId)
            {
               credentials.steamAuthTicket = "override-authticket";
               credentials.commit();
               overrideCommitted = true;
            }
            else
            {
               credentials.steamAuthTicketHandle = config.steamworks.SteamUser_GetAuthSessionTicketHandle();
               if(credentials.steamAuthTicketHandle)
               {
                  credentials.steamAuthTicket = config.steamworks.SteamUser_GetAuthSessionTicket(credentials.steamAuthTicketHandle);
                  logger.info("PreAuthState.handleEnteredState STEAM TICKET=" + credentials.steamAuthTicketHandle + "/" + credentials.steamAuthTicket);
                  if(credentials.steamAuthTicket)
                  {
                     credentials.commit();
                     return;
                  }
               }
            }
         }
         if(config.runMode.autologin)
         {
            credentials.vbb_name = "kiosk";
            credentials.password = "kiosk";
            if(Math.random() > 0.5)
            {
               credentials.displayName = config.gameGuiContext.randomMaleName;
            }
            else
            {
               credentials.displayName = config.gameGuiContext.randomFemaleName;
            }
            credentials.commit();
            return;
         }
         // PATCH begin (#2, #96): the stock game ended here with an "Authenticating..." dialog and
         // waited for a username and password that no screen asks for, so it hung. The test
         // route above has already committed and keeps its stock ending; every other way of
         // getting here means Steam gave nothing usable, so the player is told why and asked.
         // The game never moves to Discord by itself: a Steam owner whose Steam is closed would
         // land in a new, empty Discord account (BSF-Custom-Server #391).
         if(overrideCommitted)
         {
            data.setValue(GameStateDataEnum.SHOW_LOGIN_SCREEN,true);
            return;
         }
         showSteamFailedDialog();
         // PATCH end
      }

      // PATCH begin (#96)
      private function showSteamFailedDialog() : void
      {
         var reason:String;
         steamFailedRemember = !DiscordSignIn.steamUnchecked && !config.options.overrideSteamId;
         if(DiscordSignIn.steamUnchecked)
         {
            reason = "The server couldn\'t check your Steam account just now. This usually passes in a moment.";
         }
         else if(DiscordSignIn.steamRefused)
         {
            reason = "The server didn\'t accept your Steam account.";
         }
         else if(!credentials.steamId)
         {
            // #97: a Steam account that doesn't own Factions fails Steam's start-up exactly like
            // a closed Steam (StartState), so both causes are named, each with its own action.
            reason = "Steam isn\'t running, or this Steam account doesn\'t have Factions.";
         }
         else
         {
            reason = "Steam didn\'t confirm your account.";
         }
         logger.info("PreAuthState Steam sign-in not possible (" + reason + "); asking the player");
         // Kept short: the stock dialog centres its body in a fixed box, so a longer body rides up
         // into the title and loses its last line (GuiDialog in the decompile). "Start Steam" is
         // no help when the server refused the account, so that case leaves it out.
         var body:String = reason + "\n";
         if(DiscordSignIn.steamUnchecked)
         {
            body += "Steam and Discord are separate accounts. Choosing Discord now isn\'t remembered.";
         }
         else
         {
            if(DiscordSignIn.steamRefused)
            {
               body += "Sign in with Discord instead.";
            }
            else if(!credentials.steamId)
            {
               body += "No Factions on Steam? Sign in with Discord.\nHave it on Steam? Quit, start Steam, then restart the game.";
            }
            else
            {
               body += "Quit, restart Steam, then the game. Or sign in with Discord.";
            }
            body += "\nSteam and Discord are separate accounts.";
         }
         // The game shows one dialog at a time, so the stock "Authenticating... Please wait."
         // dialog (LoginPage), which has no buttons, would take this one's place.
         data.setValue(GameStateDataEnum.SHOW_LOGIN_SCREEN,false);
         // PATCH (#97): after a passing fault, a second try at Steam takes Quit's place. Closing
         // the window still quits.
         var firstButton:String = USE_DISCORD;
         var secondButton:String = QUIT;
         if(DiscordSignIn.steamUnchecked)
         {
            firstButton = TRY_STEAM;
            secondButton = USE_DISCORD;
         }
         closeSteamFailedDialog();
         steamFailedDialog = config.gameGuiContext.createDialog();
         steamFailedDialog.openTwoBtnDialog("Couldn\'t sign in with Steam",body,firstButton,secondButton,steamFailedDialogHandler);
         DiscordSignIn.enlarge(steamFailedDialog);
      }

      private function closeSteamFailedDialog() : void
      {
         if(steamFailedDialog)
         {
            // Cleared first: closing calls the handler with no button, which must be a no-op.
            var closing:IGuiDialog = steamFailedDialog;
            steamFailedDialog = null;
            closing.closeDialog(null);
         }
      }

      private function steamFailedDialogHandler(button:String) : void
      {
         if(!button || !steamFailedDialog)
         {
            return;
         }
         // A button press has already closed the dialog.
         steamFailedDialog = null;
         if(button == TRY_STEAM)
         {
            logger.info("PreAuthState player chose to try Steam again");
            trySteamAgain();
            return;
         }
         if(button == QUIT)
         {
            logger.info("PreAuthState player chose to quit instead of signing in with Discord");
            // The same way out as the "Login Failed" dialog's Disconnect button (LoginPage).
            config.context.appInfo.terminateError("Steam sign-in not possible; player quit");
            return;
         }
         logger.info("PreAuthState player chose Discord" + (steamFailedRemember ? "; remembered for next launch" : "; not remembered"));
         if(steamFailedRemember)
         {
            DiscordSignIn.saveRoute(config,DiscordSignIn.ROUTE_DISCORD,logger);
         }
         startDiscordSignIn();
      }
      // PATCH end

      // PATCH begin (#97): "Try Steam again", after the server couldn't check Steam just now. It
      // asks Steam for a new proof rather than sending the one the server couldn't check, and
      // runs only when the player presses the button: the game never tries again by itself. If
      // the server can't check the new proof either, AuthState brings the question back.
      private function trySteamAgain() : void
      {
         cancelSteamProof();
         DiscordSignIn.steamUnchecked = false;
         chooseSignIn();
      }

      // Tells Steam the old proof is no longer needed, which Steam asks of every proof it hands
      // out; the stock game never did. Logs the proof's number only, never the proof itself.
      private function cancelSteamProof() : void
      {
         var handle:int = credentials.steamAuthTicketHandle;
         credentials.steamAuthTicket = null;
         credentials.steamAuthTicketHandle = 0;
         // Nothing to cancel: Steam handed out no proof, or the --steam_id test route made one up.
         if(!handle || config.options.overrideSteamId || !config.steamworks.enabled)
         {
            return;
         }
         logger.info("PreAuthState cancelling Steam proof " + handle);
         try
         {
            config.steamworks.SteamUser_CancelAuthTicket(handle);
         }
         catch(e:Error)
         {
            logger.info("PreAuthState could not cancel Steam proof " + handle + ": " + e.message);
         }
      }
      // PATCH end

      // PATCH begin (#2)
      private function startDiscordSignIn() : void
      {
         logger.info("PreAuthState starting Discord sign-in");
         // PATCH (#96): from here on, every sign-in in this run goes to Discord.
         DiscordSignIn.discordThisRun = true;
         // The same stand-in --steam false uses, so nothing later calls into a Steam that
         // failed or whose proof was refused.
         if(config.steamworks.enabled)
         {
            config.steamworks = new NullSteamworks(false);
         }
         credentials.steamId = null;
         credentials.steamAuthTicket = null;
         credentials.steamAuthTicketHandle = 0;
         // A key from an earlier hand-off is used up; drop it so it is never sent again.
         if(DiscordSignIn.isDiscordPassword(credentials.password))
         {
            credentials.password = null;
         }
         // The game shows one dialog at a time, so the stock "Authenticating... Please wait."
         // dialog (LoginPage), which has no buttons, would take the Discord one's place.
         data.setValue(GameStateDataEnum.SHOW_LOGIN_SCREEN,false);
         if(discord)
         {
            discord.stop();
         }
         discord = new DiscordSignIn(config,credentials,communicator,data,logger);
         discord.start();
      }
      // PATCH end

      override protected function handleCleanup() : void
      {
         credentials.removeEventListener("Credentials.EVENT_COMMITTED",credentialsChangeEvent);
         // PATCH begin (#2, #96): leaving this state, by any route, ends the hand-off and
         // closes the question.
         closeSteamFailedDialog();
         if(discord)
         {
            discord.stop();
            discord = null;
         }
         // PATCH end
      }

      protected function credentialsChangeEvent(param1:Event) : void
      {
         if(credentials.valid)
         {
            phase = StatePhase.COMPLETED;
         }
      }
   }
}
