package game.session.states
{
   import engine.core.fsm.Fsm;
   import engine.core.fsm.StateData;
   import engine.core.fsm.StatePhase;
   import engine.core.logging.ILogger;
   import engine.steamworks.NullSteamworks;
   import flash.events.Event;
   import game.session.GameState;

   public class PreAuthState extends GameState
   {

      // PATCH (#2): the Discord sign-in in progress, when Steam could not be used.
      private var discord:DiscordSignIn;

      public function PreAuthState(param1:StateData, param2:Fsm, param3:ILogger)
      {
         super(param1,param2,param3);
      }

      override protected function handleEnteredState() : void
      {
         // PATCH (#2): true once the --steam_id test route has committed its made-up proof.
         var overrideCommitted:Boolean = false;
         if(gameFsm.config.options.alwaysOffline)
         {
            phase = StatePhase.COMPLETED;
            return;
         }
         credentials.addEventListener("Credentials.EVENT_COMMITTED",credentialsChangeEvent);
         gameFsm.logout();
         // PATCH (#2): skip Steam once the server has refused its proof (AuthState sets this).
         if(credentials.steamId && !DiscordSignIn.steamRefused)
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
         // PATCH begin (#2): the stock game ended here with an "Authenticating..." dialog and
         // waited for a username and password that no screen asks for, so it hung. The test
         // route above has already committed and keeps its stock ending; every other way of
         // getting here means Steam gave nothing usable — not running, no proof, or a proof
         // the server refused — so sign in through Discord instead.
         if(overrideCommitted)
         {
            data.setValue(GameStateDataEnum.SHOW_LOGIN_SCREEN,true);
            return;
         }
         startDiscordSignIn();
         // PATCH end
      }

      // PATCH begin (#2)
      private function startDiscordSignIn() : void
      {
         logger.info("PreAuthState no usable Steam sign-in; starting Discord sign-in");
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
         // Keeps the stock "Authenticating... Please wait." dialog (LoginPage) from opening
         // underneath the Discord one, which has the buttons.
         data.setValue(GameStateDataEnum.SHOW_LOGIN_SCREEN,false);
         discord = new DiscordSignIn(config,credentials,communicator,data,logger);
         discord.start();
      }
      // PATCH end

      override protected function handleCleanup() : void
      {
         credentials.removeEventListener("Credentials.EVENT_COMMITTED",credentialsChangeEvent);
         // PATCH begin (#2): leaving this state, by any route, ends the hand-off.
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
