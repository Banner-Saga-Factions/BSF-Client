package game.saga
{
   import engine.battle.fsm.BattleFinishedData;
   import engine.resource.ResourceManager;
   import engine.saga.Saga;
   import engine.saga.SagaDef;
   import engine.saga.WarOutcome;
   import engine.saga.convo.Convo;
   import game.cfg.GameConfig;
   import game.session.states.AssembleHeroesState;
   import game.session.states.FlashState;
   import game.session.states.GameStateDataEnum;
   import game.session.states.MapCampLoadState;
   import game.session.states.SceneLoadState;
   import game.session.states.SceneState;
   
   public class GameSaga extends Saga
   {
      
      public var config:GameConfig;
      
      private var saved:Vector.<SavedSceneState> = new Vector.<SavedSceneState>();
      
      private var campSaved:SavedSceneState;
      
      public function GameSaga(param1:GameConfig, param2:SagaDef, param3:ResourceManager)
      {
         super(param2,param1.soundSystem,param3,param1.logger);
         this.config = param1;
      }
      
      override protected function performCamped() : String
      {
         return null;
      }
      
      override public function sceneStateSave() : String
      {
         var _loc1_:SavedSceneState = null;
         var _loc2_:SceneState = config.fsm.current as SceneState;
         if(_loc2_)
         {
            if(!_loc2_.scene.boards || _loc2_.scene.boards.length == 0)
            {
               logger.info("   --- SCENE SAVE " + _loc2_.loader.url);
               _loc1_ = new SavedSceneState();
               _loc1_.save(_loc2_);
               saved.push(_loc1_);
               return _loc1_.url;
            }
         }
         return null;
      }
      
      override public function sceneStateRestore() : String
      {
         var _loc1_:SavedSceneState = null;
         if(saved.length > 0)
         {
            _loc1_ = saved.pop();
            logger.info("   --- SCENE RESTORE " + _loc1_.url);
            return _loc1_.restore(this);
         }
         return null;
      }
      
      override public function campSceneStateClear() : void
      {
         campSaved = null;
      }
      
      private function campSceneStateSave() : String
      {
         var _loc1_:SceneState = config.fsm.current as SceneState;
         if(_loc1_)
         {
            if(_loc1_.scene.landscape.travel)
            {
               if(!_loc1_.scene.boards || _loc1_.scene.boards.length == 0)
               {
                  campSaved = new SavedSceneState();
                  campSaved.save(_loc1_);
               }
            }
         }
         return campSaved ? campSaved.url : null;
      }
      
      override public function campSceneStateRestore() : String
      {
         var _loc1_:SavedSceneState = null;
         if(campSaved)
         {
            _loc1_ = campSaved;
            campSaved = null;
            logger.info("   --- CAMP SCENE RESTORE " + _loc1_.url);
            return _loc1_.restore(this);
         }
         return null;
      }
      
      override public function performConversationStart(param1:Convo) : void
      {
         campSceneStateSave();
         super.performConversationStart(param1);
         config.fsm.current.data.removeValue(GameStateDataEnum.HAPPENING_ID);
         config.fsm.current.data.setValue(GameStateDataEnum.CONVO,param1);
         config.fsm.current.data.setValue(GameStateDataEnum.SCENE_URL,param1.sceneUrl);
         config.fsm.transitionTo(SceneLoadState,config.fsm.current.data);
      }
      
      override public function performTravelStart(param1:String, param2:String, param3:Number, param4:String, param5:Boolean) : void
      {
         if(!caravan)
         {
            logger.error("performTravelStart with no caravan");
            return;
         }
         if(param5)
         {
            saved.splice(0,saved.length);
            camped = false;
         }
         super.performTravelStart(param1,param2,param3,param4,param5);
         config.fsm.current.data.setValue(GameStateDataEnum.HAPPENING_ID,param4);
         config.fsm.current.data.setValue(GameStateDataEnum.CONVO,null);
         config.fsm.current.data.setValue(GameStateDataEnum.SCENE_URL,param1);
         config.fsm.current.data.setValue(GameStateDataEnum.TRAVEL_POSITION,param3);
         config.fsm.current.data.setValue(GameStateDataEnum.TRAVEL_LOCATION,param2);
         config.fsm.current.data.setValue(GameStateDataEnum.SCENE_IS_TOWN,false);
         config.fsm.transitionTo(SceneLoadState,config.fsm.current.data);
      }
      
      override public function performBattleStart(param1:String, param2:String, param3:String, param4:int, param5:String, param6:String) : void
      {
         if(!caravan)
         {
            logger.error("performBattleStart with no caravan");
            return;
         }
         campSceneStateSave();
         super.performBattleStart(param1,param2,param3,param4,param5,param6);
         config.fsm.current.data.setValue(GameStateDataEnum.HAPPENING_ID,param2);
         config.fsm.current.data.setValue(GameStateDataEnum.MATCH_RESOLUTION_CONTINUE_ONLY,true);
         config.fsm.current.data.setValue(GameStateDataEnum.LOCAL_PARTY,caravan.legend.party.getEntityListDef());
         config.fsm.current.data.setValue(GameStateDataEnum.SCENE_URL,param1);
         config.fsm.current.data.removeValue(GameStateDataEnum.CONVO);
         config.fsm.current.data.removeValue(GameStateDataEnum.TRAVEL_POSITION);
         config.fsm.current.data.removeValue(GameStateDataEnum.TRAVEL_LOCATION);
         config.fsm.current.data.setValue(GameStateDataEnum.SCENE_IS_TOWN,false);
         config.fsm.current.data.setValue(GameStateDataEnum.BATTLE_BUCKET,param3);
         config.fsm.current.data.setValue(GameStateDataEnum.BATTLE_BUCKET_QUOTA,param4);
         config.fsm.current.data.setValue(GameStateDataEnum.BATTLE_SPAWN_TAGS,param6);
         config.fsm.current.data.setValue(GameStateDataEnum.BATTLE_BUCKET_DEPLOYMENT,param5);
         config.fsm.transitionTo(SceneLoadState,config.fsm.current.data);
      }
      
      override public function performSceneStart(param1:String, param2:String) : void
      {
         campSceneStateSave();
         super.performSceneStart(param1,param2);
         config.fsm.current.data.setValue(GameStateDataEnum.HAPPENING_ID,param2);
         config.fsm.current.data.setValue(GameStateDataEnum.SCENE_URL,param1);
         config.fsm.current.data.removeValue(GameStateDataEnum.CONVO);
         config.fsm.current.data.removeValue(GameStateDataEnum.TRAVEL_POSITION);
         config.fsm.current.data.removeValue(GameStateDataEnum.TRAVEL_LOCATION);
         config.fsm.current.data.setValue(GameStateDataEnum.SCENE_IS_TOWN,false);
         config.fsm.transitionTo(SceneLoadState,config.fsm.current.data);
      }
      
      override public function performMapCamp() : void
      {
         sceneStateSave();
         config.fsm.current.data.removeValue(GameStateDataEnum.SCENE_URL);
         config.fsm.current.data.removeValue(GameStateDataEnum.HAPPENING_ID);
         config.fsm.current.data.removeValue(GameStateDataEnum.CONVO);
         config.fsm.transitionTo(MapCampLoadState,config.fsm.current.data);
      }
      
      override public function performAssembleHeroes() : void
      {
         campSceneStateSave();
         sceneStateSave();
         config.fsm.transitionTo(AssembleHeroesState,config.fsm.current.data);
      }
      
      override public function performFlashPage(param1:String, param2:String, param3:Number) : void
      {
         campSceneStateSave();
         super.performFlashPage(param1,param2,param3);
         config.fsm.current.data.setValue(GameStateDataEnum.FLASH_URL,param1);
         config.fsm.current.data.setValue(GameStateDataEnum.FLASH_TIME,param3);
         config.fsm.current.data.setValue(GameStateDataEnum.FLASH_MSG,param2);
         config.fsm.transitionTo(FlashState,config.fsm.current.data);
      }
      
      override public function performPoppening(param1:Convo, param2:Boolean) : void
      {
         super.performPoppening(param1,param2);
         if(param2)
         {
            config.pageManager.war = param1;
         }
         else
         {
            config.pageManager.poppening = param1;
         }
      }
      
      override public function performWarResolution(param1:WarOutcome, param2:BattleFinishedData) : void
      {
         super.performWarResolution(param1,param2);
         var _loc3_:SceneState = config.fsm.current as SceneState;
         if(_loc3_)
         {
            _loc3_.showWarResolution(param1,param2);
         }
      }
      
      override public function performWarRespawn() : void
      {
         super.performWarRespawn();
         var _loc1_:SceneState = config.fsm.current as SceneState;
         if(_loc1_)
         {
            _loc1_.respawnBattle();
         }
      }
   }
}

import engine.landscape.travel.model.Travel;
import game.session.states.SceneState;
import game.saga.GameSaga; // JPEXS artifact fix: file-internal class below needs the package class.

class SavedSceneState
{
   
   public var url:String;
   
   public var travel_position:Number = -1;
   
   public function SavedSceneState()
   {
      super();
   }
   
   public function save(param1:SceneState) : void
   {
      clear();
      if(!param1)
      {
         return;
      }
      url = param1.loader.url;
      var _loc2_:Travel = param1 ? param1.scene.landscape.travel : null;
      if(_loc2_)
      {
         travel_position = _loc2_.position;
      }
   }
   
   public function clear() : void
   {
      url = null;
      travel_position = -1;
   }
   
   public function restore(param1:GameSaga) : String
   {
      if(!url)
      {
         return null;
      }
      if(travel_position >= 0)
      {
         param1.performTravelStart(url,null,travel_position,null,true);
      }
      else
      {
         param1.performSceneStart(url,null);
      }
      return url;
   }
}
