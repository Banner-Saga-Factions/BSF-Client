package game.session.states
{
   import engine.core.fsm.Fsm;
   import engine.core.fsm.StateData;
   import engine.core.fsm.StatePhase;
   import engine.core.logging.ILogger;
   import game.session.GameState;
   import game.session.actions.AuthTxn;
   
   public class AuthState extends GameState
   {
      
      private static const LOCAL_BUILD_NUMBER:String = "locally";
      
      private var action:AuthTxn;
      
      public function AuthState(param1:StateData, param2:Fsm, param3:ILogger)
      {
         super(param1,param2,param3);
      }
      
      override protected function handleCleanup() : void
      {
         if(action)
         {
            action.abort();
            action = null;
         }
      }
      
      override protected function handleEnteredState() : void
      {
         credentials.offline = false;
         communicator.connected = false;
         if(gameFsm.config.options.alwaysOffline)
         {
            phase = StatePhase.COMPLETED;
            return;
         }
         action = new AuthTxn(credentials,config.client_language,authCallbackHandler,config.logger);
         logger.info("AuthState AUTHENTICATING " + communicator.hostUrl + ", " + credentials.vbb_name + ": " + credentials.childNumber + " steam=" + credentials.steamId);
         action.send(communicator);
      }
      
      private function authCallbackHandler(param1:AuthTxn) : void
      {
         if(param1 != this.action)
         {
            return;
         }
         var _loc2_:Boolean = data.getValue(GameStateDataEnum.AUTH_REQUIRE);
         if(param1 && param1.success && param1.jsonObject)
         {
            config.systemMessage.msg = param1.jsonObject.system_msg;
            communicator.connected = true;
            if(param1.buildNumber != config.context.appInfo.buildVersion)
            {
               logger.info("Server build number is " + param1.buildNumber + ", but ours is " + config.context.appInfo.buildVersion + ", seeking confirmation");
               if(config.context.appInfo.buildVersion != "locally" && param1.buildNumber != "locally")
               {
                  this.action = null;
                  data.setValue(GameStateDataEnum.BUILD_NUMBER,param1.buildNumber);
                  if(_loc2_)
                  {
                     gameFsm.transitionTo(AuthBuildMismatchState,data);
                  }
                  else
                  {
                     phase = StatePhase.COMPLETED;
                  }
                  return;
               }
            }
            if(!credentials.valid || !credentials.displayName || !credentials.userId || !credentials.sessionKey)
            {
               logger.error("Invalid credentials: " + credentials);
               data.setValue(GameStateDataEnum.SERVER_MESSAGE,"Invalid Credentials");
               phase = StatePhase.FAILED;
               return;
            }
            phase = StatePhase.COMPLETED;
         }
         else if(param1.canRetry)
         {
            // PATCH begin (#2): a Discord sign-in is never sent twice. The server may already have
            // used up its key, and a second try would then be told "expired", hiding the reason.
            if(DiscordSignIn.isDiscordPassword(credentials.password))
            {
               logger.info("AuthState Discord sign-in got " + param1.responseCode + "; not sending it again");
               this.action.abort();
               this.action = null;
               data.setValue(GameStateDataEnum.SERVER_MESSAGE,"Could not finish signing in. Press Retry to start again.");
               phase = StatePhase.FAILED;
               return;
            }
            // PATCH end
            if(_loc2_)
            {
               param1.resend(communicator,5000);
            }
            else
            {
               phase = StatePhase.COMPLETED;
            }
         }
         else
         {
            // PATCH begin (#2): the server refused the Steam proof (401), or the Steam id
            // (400). Go straight to the Discord sign-in — before the stock code below, which
            // would swallow the refusal now and ask with the same proof again later.
            if(isRefusedSteamSignIn(param1))
            {
               logger.info("AuthState Steam sign-in refused (" + param1.responseCode + "); switching to Discord sign-in");
               this.action.abort();
               this.action = null;
               DiscordSignIn.steamRefused = true;
               gameFsm.transitionTo(PreAuthState,data);
               return;
            }
            // PATCH end
            this.action.abort();
            this.action = null;
            data.setValue(GameStateDataEnum.SERVER_MESSAGE,param1.message);
            if(_loc2_)
            {
               phase = StatePhase.FAILED;
            }
            else
            {
               phase = StatePhase.COMPLETED;
            }
         }
      }

      // PATCH begin (#2): a Steam sign-in carries a Steam proof and no Discord key. The
      // server's Steam refusals are 401 (proof not accepted) and 400 (id not usable, or held
      // by a Discord player). A refused Discord sign-in is not one: it goes to "Login Failed".
      // Only the first refusal in a run counts: kiosk mode sends the refused proof again, and
      // without this it would go round in a loop.
      private function isRefusedSteamSignIn(param1:AuthTxn) : Boolean
      {
         if(DiscordSignIn.steamRefused || !credentials.steamAuthTicket || DiscordSignIn.isDiscordPassword(credentials.password))
         {
            return false;
         }
         return param1.responseCode == 401 || param1.responseCode == 400;
      }
      // PATCH end
   }
}

