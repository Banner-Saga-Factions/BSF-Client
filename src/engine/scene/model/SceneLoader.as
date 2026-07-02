package engine.scene.model
{
   import engine.battle.board.def.BattleBoardDef;
   import engine.battle.board.model.BattleBoard;
   import engine.core.logging.ILogger;
   import engine.entity.def.EntityListDefVars;
   import engine.entity.def.IEntityListDef;
   import engine.resource.ResourceMonitor;
   import engine.resource.def.DefResource;
   import engine.saga.convo.Convo;
   import engine.scene.SceneContext;
   import engine.scene.def.SceneDef;
   import engine.scene.def.SceneDefVars;
   import engine.scene.view.SceneView;
   import flash.errors.IllegalOperationError;
   import flash.events.Event;
   import tbs.srv.battle.data.BattlePartyData;
   import tbs.srv.battle.data.client.BattleCreateData;
   
   public class SceneLoader
   {
      
      public var _url:String;
      
      public var def:SceneDef;
      
      public var scene:Scene;
      
      public var view:SceneView;
      
      public var monitor:ResourceMonitor;
      
      public var resource:DefResource;
      
      public var completeCallback:Function;
      
      public var context:SceneContext;
      
      private var finished:Boolean;
      
      public var ok:Boolean;
      
      private var battleCreateData:BattleCreateData;
      
      private var battleOrder:int;
      
      private var isOnline:Boolean;
      
      private var opponent:BattlePartyData;

      // Offline vs-AI: a mirrored CPU roster injected into the opposite deployment area.
      // null for normal online battles (the optional ctor param defaults to null).
      private var aiOpponent:IEntityListDef;

      public var convo:Convo;
      
      public var happeningId:String;
      
      public var board_id:String = "board_0";
      
      public var view_factory:Function;
      
      public var battle_bucket:String;
      
      public var battle_bucket_quota:int;
      
      public var battle_bucket_deployment:String;
      
      public var setupLocalPartyCallback:Function;
      
      public function SceneLoader(param1:String, param2:SceneContext, param3:Function, param4:Function, param5:BattlePartyData, param6:BattleCreateData, param7:int, param8:Boolean, param9:Convo, param10:String, param11:String, param12:int, param13:String, param14:IEntityListDef = null)
      {
         super();
         this.monitor = new ResourceMonitor(param2.logger,resourceMonitorHandler);
         this.opponent = param5;
         this._url = param1;
         this.context = param2;
         this.completeCallback = param3;
         this.battleOrder = param7;
         this.battleCreateData = param6;
         this.isOnline = param8;
         this.convo = param9;
         this.happeningId = param10;
         this.battle_bucket = param11;
         this.battle_bucket_quota = param12;
         this.battle_bucket_deployment = param13;
         this.setupLocalPartyCallback = param4;
         this.aiOpponent = param14;
      }
      
      public function get logger() : ILogger
      {
         return context.logger;
      }
      
      public function pause() : void
      {
         if(view)
         {
            view.pause();
         }
         if(scene)
         {
            scene.pause();
         }
      }
      
      public function resume() : void
      {
         if(view)
         {
            view.resume();
         }
         if(scene)
         {
            scene.resume();
         }
      }
      
      public function cleanup() : void
      {
         if(view)
         {
            view.cleanup();
            view = null;
         }
         if(scene)
         {
            scene.cleanup();
            scene = null;
         }
         if(resource)
         {
            resource.removeResourceListener(defrCompleteHandler);
            resource.release();
            resource = null;
         }
         if(monitor)
         {
            monitor.cleanup();
            monitor = null;
         }
      }
      
      private function resourceMonitorHandler(param1:ResourceMonitor) : void
      {
         checkFinished();
      }
      
      public function load(param1:SceneDef) : void
      {
         logger.debug("SceneLoader.load " + url);
         context.resman.addMonitor(monitor);
         if(param1)
         {
            this.def = param1;
            loadFromDef();
         }
         else
         {
            resource = context.resman.getResource(url,DefResource) as DefResource;
            resource.addResourceListener(defrCompleteHandler);
         }
      }
      
      private function loadFromDef() : void
      {
         var _loc5_:BattleBoardDef = null;
         var _loc3_:BattleBoard = null;
         var _loc4_:String = null;
         var _loc2_:Boolean = false;
         var _loc1_:Object = null;
         var _loc6_:EntityListDefVars = null;
         try
         {
            scene = new Scene(def,context,battleCreateData,battleOrder);
            scene.convo = convo;
            if(board_id)
            {
               _loc5_ = def.getBoard(board_id);
               logger.debug("SceneLoader.defrCompleteHandler board_0=" + _loc5_);
               if(_loc5_)
               {
                  _loc3_ = scene.prepareBoard("board_0",isOnline);
                  if(setupLocalPartyCallback != null)
                  {
                     setupLocalPartyCallback(_loc3_);
                  }
                  if(opponent)
                  {
                     _loc4_ = _loc3_.def.getDeploymentAreaIdByIndex(opponent.party_index);
                     _loc2_ = false;
                     _loc1_ = {"defs":opponent.defs};
                     _loc6_ = new EntityListDefVars(context.locale).fromJson(_loc1_,logger,context.abilities,context.classes);
                     _loc3_.addRemoteParty(opponent.display_name,opponent.user.toString(),opponent.team,_loc4_,_loc6_,opponent.timer,_loc2_);
                     _loc3_.shouldSpawnAi = false;
                  }
                  if(aiOpponent != null)
                  {
                     // Offline vs-AI: drop the mirrored CPU party into the OPPOSITE deployment
                     // area (player/spectator side is index 0), pre-deployed, and stop the scene's
                     // own spawners from also adding enemies. Parallels the online opponent block
                     // above; "ai" is a distinct team so mirrored ids don't collide with the player.
                     _loc4_ = _loc3_.def.getDeploymentAreaIdByIndex(battleOrder == 0 ? 1 : 0);
                     _loc3_.addAiParty("AI","ai","ai",_loc4_,aiOpponent,0,false);
                     _loc3_.shouldSpawnAi = false;
                  }
                  _loc3_.bucket = battle_bucket;
                  _loc3_.bucket_quota = battle_bucket_quota;
                  _loc3_.bucket_deployment = battle_bucket_deployment;
                  _loc3_.enabled = true;
                  scene.focusedBoard = _loc3_;
               }
            }
            if(view_factory != null)
            {
               view = view_factory(scene,context.soundDriver);
            }
            else
            {
               view = new SceneView(scene,context.soundDriver);
            }
            ok = true;
            checkFinished();
            return;
         }
         catch(e:Error)
         {
            context.logger.error("SceneLoader.loadFromDef failed to load Scene [" + url + "]: " + e + " " + e.getStackTrace());
         }
         abort();
      }
      
      protected function defrCompleteHandler(param1:Event) : void
      {
         logger.debug("SceneLoader.defrCompleteHandler " + resource + " ok=" + resource.ok);
         if(!resource.ok)
         {
            logger.error("SceneLoader.defrCompleteHandler FAILED " + resource);
            if(completeCallback != null)
            {
               completeCallback(this);
            }
            return;
         }
         try
         {
            def = new SceneDefVars().fromJson(resource.jo,context.locale,context.classes,context.abilities,context.triggers,context.logger);
            def.url = url;
            loadFromDef();
            return;
         }
         catch(e:Error)
         {
            context.logger.error("SceneLoader failed to load Scene [" + url + "]: " + e + " " + e.getStackTrace());
         }
         abort();
      }
      
      private function abort() : void
      {
         if(monitor)
         {
            monitor.abort();
         }
         if(completeCallback != null)
         {
            completeCallback(this);
         }
      }
      
      private function checkFinished() : void
      {
         if(finished)
         {
            throw new IllegalOperationError("already finished");
         }
         if(monitor.empty)
         {
            if(scene && view)
            {
               monitor.cleanup();
               monitor = null;
               finished = true;
               scene.start(happeningId);
               if(view)
               {
                  view.start();
               }
               if(completeCallback != null)
               {
                  completeCallback(this);
               }
            }
         }
         else if(logger.debugEnabled)
         {
         }
      }
      
      public function get url() : String
      {
         return _url;
      }
   }
}

