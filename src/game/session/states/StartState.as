package game.session.states
{
   import engine.core.fsm.Fsm;
   import engine.core.fsm.StateData;
   import engine.core.fsm.StatePhase;
   import engine.core.logging.ILogger;
   import engine.steamworks.NullSteamworks;
   import game.session.GameState;
   import tbs.srv.battle.data.client.BattleCreateData;
   
   public class StartState extends GameState
   {
      
      public function StartState(param1:StateData, param2:Fsm, param3:ILogger)
      {
         super(param1,param2,param3);
      }
      
      override protected function handleEnteredState() : void
      {
         var _loc1_:int = 0;
         var _loc2_:BattleCreateData = null;
         if(config.steamworks.enabled && !config.steamworks.initialized)
         {
            // PATCH begin (#2): the stock game showed "Steam Error" here and closed when Ok was
            // pressed. Carry on without Steam instead, using the same stand-in --steam false
            // uses (so nothing later calls into the Steam that failed); with no Steam id,
            // PreAuthState signs in through Discord.
            logger.info("StartState Steam did not start; carrying on without it, to sign in through Discord");
            config.steamworks = new NullSteamworks(false);
            // PATCH end
         }
         if(config.options.overrideSteamId)
         {
            credentials.steamId = config.options.overrideSteamId;
            credentials.displayName = "∏" + config.options.overrideSteamId;
         }
         else
         {
            credentials.steamId = config.steamworks.SteamUser_GetSteamID();
            config.client_language = config.steamworks.SteamApps_GetCurrentGameLanguage();
            if(!credentials.steamId)
            {
               logger.info("StartState.handleEnteredState $$ NO STEAM ID");
            }
            else
            {
               _loc1_ = config.steamworks.SteamID_GetAccountId(credentials.steamId);
               logger.info("StartState.handleEnteredState $$ STEAM ID=" + credentials.steamId + ", account " + _loc1_);
               credentials.displayName = config.steamworks.SteamFriends_GetPersonaName();
            }
         }
         if(config.options.startInCombat)
         {
            logger.info("StartState.handleEnteredState $$ starting in combat");
            _loc2_ = new BattleCreateData();
            _loc2_.scene = config.options.startInCombat;
            data.setValue(GameStateDataEnum.BATTLE_CREATE_DATA,_loc2_);
            data.setValue(GameStateDataEnum.SCENE_URL,config.options.startInCombat);
            data.setValue(GameStateDataEnum.LOCAL_PARTY,config.legend.party.getEntityListDef());
            data.setValue(GameStateDataEnum.LOCAL_TIMER_SECS,0);
            config.fsm.transitionTo(SceneLoadState,data);
            return;
         }
         logger.info("StartState.handleEnteredState $$ showing login screen and completing");
         data.setValue(GameStateDataEnum.AUTOLOGIN,true);
         phase = StatePhase.COMPLETED;
      }
   }
}

