package game.session.states
{
   import engine.battle.board.model.BattleBoard;
   import engine.core.fsm.Fsm;
   import engine.core.fsm.StateData;
   import engine.core.fsm.StatePhase;
   import engine.core.logging.ILogger;
   import engine.core.util.StringUtil;
   import engine.entity.def.IEntityAppearanceDef;
   import engine.entity.def.IEntityDef;
   import engine.entity.def.IEntityListDef;
   import engine.landscape.travel.model.Travel;
   import engine.resource.AnimClipResource;
   import engine.resource.BitmapResource;
   import engine.resource.MovieClipResource;
   import engine.resource.Resource;
   import engine.resource.ResourceManager;
   import engine.resource.ResourceMonitor;
   import engine.saga.SpeakEvent;
   import engine.saga.convo.Convo;
   import engine.scene.SceneContext;
   import engine.scene.model.SceneLoader;
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.errors.IllegalOperationError;
   import game.gui.GuiIcon;
   import game.gui.GuiIconLayoutType;
   import game.gui.IGuiSpeechBubble;
   import game.session.GameState;
   import tbs.srv.battle.data.BattlePartyData;
   import tbs.srv.battle.data.client.BattleCreateData;
   
   public class SceneLoadState extends GameState
   {
      
      public static const inputDataKeys:Array = [GameStateDataEnum.SCENE_URL];
      
      private var sceneLoader:SceneLoader;
      
      private var monitor:ResourceMonitor;
      
      public function SceneLoadState(param1:StateData, param2:Fsm, param3:ILogger)
      {
         super(param1,param2,param3);
         data.setValue(GameStateDataEnum.SCENE_IS_TOWN,false);
         data.setValue(GameStateDataEnum.SCENELOADER_PRESERVE,null);
         monitor = new ResourceMonitor(config.logger,resourceMonitorChangedHandler);
      }
      
      override protected function getRequiredInputDataKeys() : Array
      {
         return inputDataKeys;
      }
      
      private function resourceMonitorChangedHandler(param1:ResourceMonitor) : void
      {
         percentLoaded = monitor.percent;
         checkReady();
      }
      
      override protected function handleEnteredState() : void
      {
         loading = true;
         config.resman.addMonitor(monitor);
         var _loc14_:SceneContext = new SceneContext(gameFsm.config.resman,gameFsm.config.guiresman,gameFsm.config.logger,gameFsm.config.abilityFactory,gameFsm.config.classes,gameFsm.config.assets.battle,gameFsm.config.soundSystem.driver,gameFsm.session,gameFsm.config.context.locale,gameFsm.config.eater,gameFsm.chat,gameFsm,gameFsm.config.animDispatcher,gameFsm.config.triggers,gameFsm.config.sceneControllerConfig,gameFsm.config.keybinder,gameFsm.config.saga,gameFsm.config.spawnables,speechBubbler,convoPortraitGenerator);
         _loc14_.staticSoundController = gameFsm.config.soundSystem.controller;
         var _loc2_:int = data.getValue(GameStateDataEnum.OPPONENT_ID);
         var _loc15_:String = data.getValue(GameStateDataEnum.OPPONENT_NAME);
         var _loc1_:int = data.getValue(GameStateDataEnum.PLAYER_ORDER);
         var _loc13_:int = _loc1_ == 0 ? 1 : 0;
         var _loc6_:IEntityListDef = data.getValue(GameStateDataEnum.OPPONENT_PARTY);
         var _loc9_:Convo = data.getValue(GameStateDataEnum.CONVO);
         var _loc5_:String = data.getValue(GameStateDataEnum.HAPPENING_ID);
         var _loc7_:String = data.getValue(GameStateDataEnum.BATTLE_BUCKET);
         var _loc12_:int = data.getValue(GameStateDataEnum.BATTLE_BUCKET_QUOTA);
         var _loc3_:String = data.getValue(GameStateDataEnum.BATTLE_BUCKET_DEPLOYMENT);
         var _loc10_:Boolean = _loc15_ ? true : false;
         var _loc8_:String = data.getValue(GameStateDataEnum.SCENE_URL);
         if(!_loc8_)
         {
            throw new IllegalOperationError("Why no URL for SceneLoadState?");
         }
         var _loc4_:BattleCreateData = data.getValue(GameStateDataEnum.BATTLE_CREATE_DATA);
         var _loc11_:BattlePartyData = null;
         if(_loc10_)
         {
            _loc11_ = _loc4_ ? _loc4_.parties[_loc13_] : null;
         }
         // Offline vs-AI: AI_OPPONENT_PARTY (an IEntityListDef, set only by AiBattleLoadState) is
         // the mirrored CPU roster; null for every other battle, so SceneLoader skips the AI block.
         sceneLoader = new SceneLoader(_loc8_,_loc14_,sceneLoaderComplete,setupLocalPartyCallback,_loc11_,_loc4_,_loc1_,_loc10_,_loc9_,_loc5_,_loc7_,_loc12_,_loc3_,data.getValue(GameStateDataEnum.AI_OPPONENT_PARTY));
         sceneLoader.load(null);
         checkReady();
      }
      
      override protected function handleCleanup() : void
      {
         super.handleCleanup();
         if(monitor)
         {
            config.resman.removeMonitor(monitor);
            monitor.cleanup();
         }
         if(sceneLoader)
         {
            sceneLoader.completeCallback = null;
            sceneLoader = null;
         }
      }
      
      private function sceneLoaderComplete(param1:SceneLoader) : void
      {
         if(param1 != sceneLoader)
         {
            return;
         }
         if(!sceneLoader.ok)
         {
            config.context.logger.error("SceneLoadState failed to load scene " + sceneLoader.url);
            monitor.abort();
            phase = StatePhase.FAILED;
            return;
         }
         checkReady();
      }
      
      protected function checkReady() : void
      {
         var _loc3_:Travel = null;
         var _loc1_:Number = NaN;
         var _loc2_:String = null;
         if(sceneLoader && monitor.empty && sceneLoader.ok)
         {
            _loc3_ = sceneLoader.scene.landscape ? sceneLoader.scene.landscape.travel : null;
            if(_loc3_)
            {
               if(data.hasValue(GameStateDataEnum.TRAVEL_POSITION))
               {
                  _loc1_ = data.getValue(GameStateDataEnum.TRAVEL_POSITION);
                  _loc3_.gotoPosition(_loc1_);
               }
               else
               {
                  _loc2_ = data.getValue(GameStateDataEnum.TRAVEL_LOCATION);
                  _loc3_.gotoLocation(_loc2_);
               }
            }
            loading = false;
            data.setValue(GameStateDataEnum.SCENE_LOADER,sceneLoader);
            config.resman.removeMonitor(monitor);
            phase = StatePhase.COMPLETED;
         }
      }
      
      public function speechBubbler(param1:SpeakEvent) : MovieClip
      {
         var _loc3_:MovieClip = null;
         var _loc2_:IGuiSpeechBubble = null;
         var _loc4_:MovieClipResource = config.guiresman.getResource("travel.swf/gui.speak_left",MovieClipResource) as MovieClipResource;
         if(_loc4_.ok)
         {
            _loc3_ = _loc4_.movieClip;
            _loc2_ = _loc3_ as IGuiSpeechBubble;
            _loc2_.init(config.gameGuiContext,param1.speaker,param1.msg,param1.timeout);
            return _loc3_;
         }
         return null;
      }
      
      public function convoPortraitGenerator(param1:IEntityDef, param2:Boolean) : Sprite
      {
         var _loc5_:Resource = null;
         var _loc6_:String = null;
         var _loc4_:ResourceManager = config.resman;
         var _loc3_:IEntityAppearanceDef = param1.appearance;
         if(param2)
         {
            _loc6_ = _loc3_.portraitUrl;
         }
         else
         {
            _loc6_ = _loc3_.backPortraitUrl;
         }
         if(!_loc6_)
         {
            logger.error("convoPortraitGenerator: no portrait for " + param1.id + " facing=" + param2);
            return null;
         }
         if(StringUtil.endsWith(_loc6_,".clip"))
         {
            _loc5_ = _loc4_.getResource(_loc6_,AnimClipResource,null);
         }
         else
         {
            if(!StringUtil.endsWith(_loc6_,".png"))
            {
               logger.error("convoPortraitGenerator: no handler for type " + _loc6_);
               return null;
            }
            _loc5_ = _loc4_.getResource(_loc6_,BitmapResource,null);
         }
         return new GuiIcon(_loc5_,GuiIconLayoutType.ACTUAL);
      }
      
      private function setupLocalPartyCallback(param1:BattleBoard) : void
      {
         var _loc5_:String = null;
         var _loc7_:String = null;
         var _loc2_:String = null;
         var _loc6_:String = null;
         if(!param1)
         {
            return;
         }
         var _loc3_:int = data.getValue(GameStateDataEnum.PLAYER_ORDER);
         var _loc4_:int = data.getValue(GameStateDataEnum.LOCAL_TIMER_SECS);
         if(_loc3_ == 0)
         {
            if(param1.numParties == 0)
            {
               _loc5_ = config.fsm.credentials.displayName;
               _loc2_ = _loc7_ = config.fsm.credentials.userId.toString();
               _loc6_ = param1.def.getDeploymentAreaIdByIndex(_loc3_);
               param1.createLocalParty(_loc5_,_loc2_,_loc7_,_loc6_,_loc4_);
            }
         }
      }
   }
}

