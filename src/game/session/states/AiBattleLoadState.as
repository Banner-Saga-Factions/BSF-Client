package game.session.states
{
   import engine.core.fsm.Fsm;
   import engine.core.fsm.StateData;
   import engine.core.logging.ILogger;
   import engine.mod.ModBridge;
   import engine.resource.ResourceGroup;
   import engine.resource.SwfResource;
   import flash.events.Event;
   import tbs.srv.battle.data.client.BattleCreateData;

   /**
    * AiBattleLoadState -- NEW FILE (not in original decompile).
    *
    * Loads an OFFLINE battle against the dormant single-player AI. Modeled on
    * TutorialBattleLoadState: it extends SceneLoadState, preloads the battle GUI, and sets up the
    * parties with NO opponent name -- so SceneLoadState computes isOnline=false and the battle
    * ENGINE makes zero server calls (no matchmaking, no Elo, no /battle/* traffic).
    *
    * The session layer is NOT affected: the long poll keeps running at its 3s default (the 1000ms
    * and 700ms battle tightenings are both gated on isOnline), and entering the battle screen still
    * sends a /game/location update -- SceneStateBattleHandler calls updateGameLocation("loc_battle")
    * with no online/offline test, and that only checks whether the SESSION is offline, not the battle.
    *
    * Two modes (same setup; the spectator flag only changes what happens downstream):
    *   - Player vs AI: LOCAL_PARTY is the human's current active party; AI_OPPONENT_PARTY is a
    *     mirror of it, injected by SceneLoader into the opposite deployment area as a CPU party.
    *   - AI vs AI spectator (SPECTATE / ModBridge.spectatorMode): side 0 is also turned into a CPU
    *     party (SceneLoadState.setupLocalPartyCallback + SceneStateBattleHandler) and the battle HUD
    *     hides local controls, so the human just watches.
    *
    * BattleCreateData.friendly=true makes SceneStateBattleHandler.onEntityKilled skip kill credit /
    * promotion / renown -- practice only, nothing is farmed.
    */
   public class AiBattleLoadState extends SceneLoadState
   {

      private var group:ResourceGroup;

      private var loadingGui:Boolean;

      public function AiBattleLoadState(param1:StateData, param2:Fsm, param3:ILogger)
      {
         group = new ResourceGroup();
         super(param1,param2,param3);

         // Scene: honor a URL supplied by the trigger (host command / debug key); otherwise default
         // to the first scene in the versus scene list. Versus maps have TWO deployment areas, which
         // the mirrored AI opponent needs -- the skirmish maps are single-area (player-only).
         var _loc1_:String = data.getValue(GameStateDataEnum.SCENE_URL);
         if(!_loc1_)
         {
            // Guard the list access: items[0] is normally a valid versus map, but if the scene list
            // hasn't loaded yet, log clearly and leave the URL null -- SceneLoadState.handleEnteredState
            // then throws its own clear "no URL" error instead of an opaque items[0]-is-undefined crash.
            if(config.sceneListDef != null && config.sceneListDef.items.length > 0)
            {
               _loc1_ = config.sceneListDef.items[0].url;
            }
            else
            {
               logger.error("AiBattleLoadState: battle scene list is empty; pass a scene URL or ensure the scene list is loaded");
            }
         }

         data.setValue(GameStateDataEnum.SCENELOADER_PRESERVE,false);
         data.setValue(GameStateDataEnum.SCENE_URL,_loc1_);

         // Mirror the player's current active battle party -- the same source the Versus and Skirmish
         // flows read. Two separate getEntityListDef() calls produce two independent EntityListDef
         // instances, so the AI side is a true copy rather than a shared reference.
         data.setValue(GameStateDataEnum.LOCAL_PARTY,config.legend.party.getEntityListDef());
         data.setValue(GameStateDataEnum.AI_OPPONENT_PARTY,config.legend.party.getEntityListDef());

         var _loc2_:BattleCreateData = new BattleCreateData();
         _loc2_.scene = _loc1_;
         _loc2_.friendly = true;
         data.setValue(GameStateDataEnum.BATTLE_CREATE_DATA,_loc2_);

         data.setValue(GameStateDataEnum.LOCAL_TIMER_SECS,0);
         data.setValue(GameStateDataEnum.PLAYER_ORDER,0);

         // Latch spectator mode from either an explicit SPECTATE value or the host's set_spectator
         // command. The "side 0 is AI too" + HUD suppression is handled downstream off this flag.
         var _loc3_:Boolean = data.getValue(GameStateDataEnum.SPECTATE) == true || ModBridge.spectatorMode;
         data.setValue(GameStateDataEnum.SPECTATE,_loc3_);

         // Preload the battle GUI swfs (same set the tutorial battle preloads). Already-cached
         // resources complete immediately, so this is cheap when launched from an in-game menu.
         config.guiresman.getResource("battle_self_popup.swf",SwfResource,group);
         config.guiresman.getResource("battle.swf",SwfResource,group);
         config.guiresman.getResource("battle_initiative.swf",SwfResource,group);
         config.guiresman.getResource("battle_enemy_popup.swf",SwfResource,group);
         config.guiresman.getResource("battle_horn.swf",SwfResource,group);
         config.guiresman.getResource("go_battle.swf",SwfResource,group);
         config.guiresman.getResource("forge_ahead.swf",SwfResource,group);
         config.guiresman.getResource("go_pillage.swf",SwfResource,group);
         config.guiresman.getResource("go_pillage2.swf",SwfResource,group);
         loadingGui = true;
         group.addResourceGroupListener(guiResourceGroupHandler);
      }

      private function guiResourceGroupHandler(param1:Event) : void
      {
         checkReady();
      }

      override protected function checkReady() : void
      {
         if(!loadingGui)
         {
            return;
         }
         if(!group.complete)
         {
            return;
         }
         super.checkReady();
      }
   }
}
