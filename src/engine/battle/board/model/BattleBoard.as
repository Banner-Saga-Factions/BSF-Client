package engine.battle.board.model
{
   import engine.battle.BattleAssetsDef;
   import engine.battle.ability.def.BattleAbilityDef;
   import engine.battle.ability.def.BattleAbilityDefFactory;
   import engine.battle.ability.effect.model.BattleFacing;
   import engine.battle.ability.model.BattleAbilityEvent;
   import engine.battle.ability.model.BattleAbilityManager;
   import engine.battle.ability.phantasm.model.VfxSequence;
   import engine.battle.board.BattleBoardEvent;
   import engine.battle.board.BattleRectangleUtils;
   import engine.battle.board.def.BattleBoardDef;
   import engine.battle.board.def.BattleBoardTriggerDef;
   import engine.battle.board.def.BattleBoardTriggerSpawner;
   import engine.battle.board.def.BattleDeploymentArea;
   import engine.battle.board.def.BattleSpawnerDef;
   import engine.battle.entity.model.BattleEntity;
   import engine.battle.entity.model.BattleEntityEvent;
   import engine.battle.entity.model.BattleEntityFactory;
   import engine.battle.fsm.BattleFsm;
   import engine.battle.sim.BattleParty;
   import engine.battle.sim.BattleSim;
   import engine.battle.sim.IBattleParty;
   import engine.core.logging.ILogger;
   import engine.entity.def.EntityDef;
   import engine.entity.def.IEntityClassDef;
   import engine.entity.def.IEntityDef;
   import engine.entity.def.IEntityListDef;
   import engine.math.Hash;
   import engine.math.MathUtil;
   import engine.resource.ResourceManager;
   import engine.saga.Saga;
   import engine.saga.SagaBucket;
   import engine.scene.model.Scene;
   import engine.sound.ISoundDriver;
   import engine.stat.def.StatType;
   import engine.stat.model.Stat;
   import engine.tile.Tile;
   import engine.tile.Tiles;
   import engine.tile.def.TileLocation;
   import engine.tile.def.TileLocationArea;
   import engine.tile.def.TileRect;
   import engine.vfx.VfxLibrary;
   import flash.errors.IllegalOperationError;
   import flash.events.EventDispatcher;
   import flash.geom.Point;
   import flash.utils.Dictionary;
   import flash.utils.getTimer;
   
   public class BattleBoard extends EventDispatcher implements IBattleBoard
   {
      
      private var _def:BattleBoardDef;
      
      private var _entities:Dictionary = new Dictionary();
      
      private var _tiles:BattleBoardTiles;
      
      private var _sim:BattleSim;
      
      private var _logger:ILogger;
      
      public var abilityFactory:BattleAbilityDefFactory;
      
      public var _resman:ResourceManager;
      
      public var assets:BattleAssetsDef;
      
      public var phantasms:BattleBoardPhantasms;
      
      public var _triggers:BattleBoardTriggers;
      
      private var _abilityManager:BattleAbilityManager;
      
      private var _enabled:Boolean;
      
      private var soundDriver:ISoundDriver;
      
      private var _selectedTile:Tile;
      
      private var partiesById:Dictionary = new Dictionary();
      
      public var parties:Vector.<IBattleParty> = new Vector.<IBattleParty>();
      
      public var scene:Scene;
      
      public var vfxs:Vector.<VfxSequence> = new Vector.<VfxSequence>();
      
      public var bucket:String;
      
      public var bucket_quota:int;
      
      private var _spawn_tags:String;
      
      public var spawn_tags_dict:Dictionary;
      
      public var bucket_deployment:String;
      
      public var vfxLibrary:VfxLibrary;
      
      private var _fake:Boolean;
      
      private var _boardSetup:Boolean;
      
      private var _deathOffset:Number = 0;
      
      public var shouldSpawnAi:Boolean = true;
      
      public var spawner2Entity:Dictionary = new Dictionary();
      
      private var updating:Boolean;
      
      public function BattleBoard(param1:BattleBoardDef, param2:Scene, param3:ILogger, param4:ResourceManager, param5:BattleAbilityDefFactory, param6:BattleAssetsDef, param7:ISoundDriver)
      {
         super();
         this.def = param1;
         this.scene = param2;
         this._logger = param3;
         this.abilityFactory = param5;
         this._resman = param4;
         this.assets = param6;
         this._abilityManager = new BattleAbilityManager(param3,param5);
         this.soundDriver = param7;
         _tiles = new BattleBoardTiles(this);
         phantasms = new BattleBoardPhantasms(this);
         _triggers = new BattleBoardTriggers(this);
         _deathOffset = -6;
         triggers.addEventListener("BattleBoardTriggerEvent.ADDED",triggersAddedHandler);
         triggers.addEventListener("BattleBoardTriggerEvent.REMOVED",triggersRemovedHandler);
         _abilityManager.addEventListener("BattleAbilityEvent.INCOMPLETES_EMPTY",incompletesEmptyHandler,false,255);
      }
      
      private function incompletesEmptyHandler(param1:BattleAbilityEvent) : void
      {
         expireDeadEntitiesEffects();
      }
      
      public function get selectedTile() : Tile
      {
         return _selectedTile;
      }
      
      public function set selectedTile(param1:Tile) : void
      {
         if(_selectedTile == param1)
         {
            return;
         }
         _selectedTile = param1;
         dispatchEvent(new BattleBoardEvent("BattleBoardEvent.SELECT_TILE"));
      }
      
      public function get deathOffset() : Number
      {
         return _deathOffset;
      }
      
      public function set deathOffset(param1:Number) : void
      {
         _deathOffset = param1;
      }
      
      public function cleanup() : void
      {
         _abilityManager.removeEventListener("BattleAbilityEvent.INCOMPLETES_EMPTY",incompletesEmptyHandler);
         triggers.removeEventListener("BattleBoardTriggerEvent.ADDED",triggersAddedHandler);
         triggers.removeEventListener("BattleBoardTriggerEvent.REMOVED",triggersRemovedHandler);
         for each(var _loc2_ in parties)
         {
            _loc2_.cleanup();
         }
         for each(var _loc1_ in entities)
         {
            _loc1_.cleanup();
         }
         _abilityManager.cleanup();
         _abilityManager = null;
         _tiles.cleanup();
         _tiles = null;
         _sim.cleanup();
         _sim = null;
         phantasms.cleanup();
         phantasms = null;
         _entities = null;
         parties = null;
      }
      
      override public function toString() : String
      {
         return def.id;
      }
      
      public function get sim() : BattleSim
      {
         return _sim;
      }
      
      public function set sim(param1:BattleSim) : void
      {
         _sim = param1;
         if(_sim)
         {
            if(_sim.fsm.battleId)
            {
               _abilityManager.seedRng = Hash.DJBHash(_sim.fsm.battleId);
            }
            else
            {
               _abilityManager.seedRng = getTimer();
            }
         }
      }
      
      private function addEntity(param1:BattleEntity) : void
      {
         if(_fake)
         {
            return;
         }
         entities[param1.id] = param1;
         param1.addEventListener("BattleEntityEvent.DAMAGED",entityDamagedHandler);
         param1.addEventListener("BattleEntityEvent.KILLING_EFFECT",entityKillingEffectHandler);
         param1.addEventListener("BattleEntityEvent.ALIVE",entityAliveHandler);
         dispatchEvent(new BattleEntityEvent("BattleEntityEvent.ADDED",param1));
      }
      
      private function entityDamagedHandler(param1:BattleEntityEvent) : void
      {
         dispatchEvent(new BattleBoardEvent("BattleBoardEvent.BOARD_ENTITY_DAMAGED",param1.entity));
      }
      
      private function entityAliveHandler(param1:BattleEntityEvent) : void
      {
         dispatchEvent(new BattleBoardEvent("BattleBoardEvent.BOARD_ENTITY_ALIVE",param1.entity));
      }
      
      private function entityKillingEffectHandler(param1:BattleEntityEvent) : void
      {
         dispatchEvent(new BattleBoardEvent("BattleBoardEvent.BOARD_ENTITY_KILLING_EFFECT",param1.entity));
      }
      
      public function removeEntity(param1:BattleEntity) : void
      {
         if(_fake)
         {
            return;
         }
         param1.removeEventListener("BattleEntityEvent.DAMAGED",entityDamagedHandler);
         param1.removeEventListener("BattleEntityEvent.ALIVE",entityAliveHandler);
         param1.removeEventListener("BattleEntityEvent.KILLING_EFFECT",entityKillingEffectHandler);
         delete entities[param1.id];
         dispatchEvent(new BattleEntityEvent("BattleEntityEvent.REMOVED",param1));
      }
      
      public function createEntity(param1:IEntityDef, param2:String, param3:Number, param4:Number, param5:IBattleParty) : BattleEntity
      {
         if(_fake)
         {
            return null;
         }
         var _loc6_:BattleEntity = BattleEntityFactory.create(this,param2,param1,param5,soundDriver,logger);
         _loc6_.setPos(param3,param4);
         addEntity(_loc6_);
         return _loc6_;
      }
      
      public function checkAllRectIntersections(param1:Number, param2:Number, param3:Number, param4:Number, param5:IBattleEntity) : uint
      {
         var _loc8_:* = 0;
         var _loc6_:uint = 0;
         for each(var _loc7_ in entities)
         {
            if(_loc7_ != param5)
            {
               _loc8_ = find2RectIntersections(param1,param2,param3,param4,_loc7_.x,_loc7_.y,_loc7_.def.entityClass.bounds.width,_loc7_.def.entityClass.bounds.length);
               _loc6_ |= _loc8_;
            }
         }
         return _loc8_;
      }
      
      public function findAllRectIntersectionEntities(param1:Number, param2:Number, param3:Number, param4:Number, param5:IBattleEntity, param6:Vector.<IBattleEntity>) : Boolean
      {
         var _loc8_:Boolean = false;
         for each(var _loc7_ in entities)
         {
            if(_loc7_ != param5)
            {
               _loc8_ = BattleRectangleUtils.test2RectIntersection(param1,param2,param3,param4,_loc7_.x,_loc7_.y,_loc7_.def.entityClass.bounds.width,_loc7_.def.entityClass.bounds.length);
               if(_loc8_)
               {
                  if(!param6)
                  {
                     return true;
                  }
                  param6.push(_loc7_);
               }
            }
         }
         return param6 && param6.length > 0;
      }
      
      public function findAllAdjacentEntities(param1:IBattleEntity, param2:Vector.<IBattleEntity>) : void
      {
         var _loc3_:BattleEntity = null;
         var _loc5_:int = int(param1.tile.x);
         var _loc4_:int = int(param1.tile.y);
         if(param1.rect.width == 1)
         {
            _loc3_ = findEntityOnTile(_loc5_,_loc4_ - 1,true,null) as BattleEntity;
            if(_loc3_ != null && param2.indexOf(_loc3_) == -1)
            {
               param2.push(_loc3_);
            }
            _loc3_ = findEntityOnTile(_loc5_ + 1,_loc4_,true,null) as BattleEntity;
            if(_loc3_ != null && param2.indexOf(_loc3_) == -1)
            {
               param2.push(_loc3_);
            }
            _loc3_ = findEntityOnTile(_loc5_,_loc4_ + 1,true,null) as BattleEntity;
            if(_loc3_ != null && param2.indexOf(_loc3_) == -1)
            {
               param2.push(_loc3_);
            }
            _loc3_ = findEntityOnTile(_loc5_ - 1,_loc4_,true,null) as BattleEntity;
            if(_loc3_ != null && param2.indexOf(_loc3_) == -1)
            {
               param2.push(_loc3_);
            }
         }
         else if(param1.rect.width == 2)
         {
            _loc3_ = findEntityOnTile(_loc5_,_loc4_ - 1,true,null) as BattleEntity;
            if(_loc3_ != null && param2.indexOf(_loc3_) == -1)
            {
               param2.push(_loc3_);
            }
            _loc3_ = findEntityOnTile(_loc5_ + 1,_loc4_ - 1,true,null) as BattleEntity;
            if(_loc3_ != null && param2.indexOf(_loc3_) == -1)
            {
               param2.push(_loc3_);
            }
            _loc3_ = findEntityOnTile(_loc5_ + 2,_loc4_,true,null) as BattleEntity;
            if(_loc3_ != null && param2.indexOf(_loc3_) == -1)
            {
               param2.push(_loc3_);
            }
            _loc3_ = findEntityOnTile(_loc5_ + 2,_loc4_ + 1,true,null) as BattleEntity;
            if(_loc3_ != null && param2.indexOf(_loc3_) == -1)
            {
               param2.push(_loc3_);
            }
            _loc3_ = findEntityOnTile(_loc5_,_loc4_ + 2,true,null) as BattleEntity;
            if(_loc3_ != null && param2.indexOf(_loc3_) == -1)
            {
               param2.push(_loc3_);
            }
            _loc3_ = findEntityOnTile(_loc5_ + 1,_loc4_ + 2,true,null) as BattleEntity;
            if(_loc3_ != null && param2.indexOf(_loc3_) == -1)
            {
               param2.push(_loc3_);
            }
            _loc3_ = findEntityOnTile(_loc5_ - 1,_loc4_ + 1,true,null) as BattleEntity;
            if(_loc3_ != null && param2.indexOf(_loc3_) == -1)
            {
               param2.push(_loc3_);
            }
            _loc3_ = findEntityOnTile(_loc5_ - 1,_loc4_,true,null) as BattleEntity;
            if(_loc3_ != null && param2.indexOf(_loc3_) == -1)
            {
               param2.push(_loc3_);
            }
         }
      }
      
      public function findEntityOnTile(param1:Number, param2:Number, param3:Boolean, param4:*) : IBattleEntity
      {
         for each(var _loc5_ in entities)
         {
            if(_loc5_ != param4)
            {
               if(!(param3 && !_loc5_.alive))
               {
                  if(BattleRectangleUtils.testPointInRect(param1 + 0.5,param2 + 0.5,_loc5_.x,_loc5_.y,_loc5_.def.entityClass.bounds.width,_loc5_.def.entityClass.bounds.length))
                  {
                     return _loc5_;
                  }
               }
            }
         }
         return null;
      }
      
      public function find2RectIntersections(param1:Number, param2:Number, param3:Number, param4:Number, param5:Number, param6:Number, param7:Number, param8:Number) : uint
      {
         if(param1 >= param5 + param7 || param1 + param3 <= param5 || param2 >= param6 + param8 || param2 + param4 <= param6)
         {
            return 0;
         }
         return 1;
      }
      
      public function get enabled() : Boolean
      {
         return _enabled;
      }
      
      public function set enabled(param1:Boolean) : void
      {
         if(_enabled != param1)
         {
            _enabled = param1;
            if(_enabled)
            {
               spawn(bucket_deployment,null);
               addBoardTriggers();
            }
            dispatchEvent(new BattleBoardEvent("BattleBoardEvent.ENABLED"));
         }
      }
      
      public function createLocalParty(param1:String, param2:String, param3:String, param4:String, param5:int) : void
      {
         createParty(param1,param2,param3,param4,BattlePartyType.LOCAL,param5,true);
      }
      
      private function createParty(param1:String, param2:String, param3:String, param4:String, param5:BattlePartyType, param6:int, param7:Boolean) : BattleParty
      {
         var _loc8_:BattleParty = partiesById[param2];
         if(!_loc8_)
         {
            _loc8_ = new BattleParty(this,param1,param2,param3,param4,param5,param6,param7);
            partiesById[param2] = _loc8_;
            parties.push(_loc8_);
            dispatchEvent(new BattleBoardEvent("BattleBoardEvent.ENABLED"));
         }
         else
         {
            if(param5 != _loc8_.type)
            {
               throw new ArgumentError("Bad party type");
            }
            if(param7 && !_loc8_.isAlly)
            {
               throw new ArgumentError("Bad enemy bool");
            }
         }
         return _loc8_;
      }
      
      public function addPartyMember(param1:String, param2:String, param3:String, param4:String, param5:String, param6:IEntityDef, param7:BattlePartyType, param8:int, param9:Boolean) : BattleEntity
      {
         var _loc12_:BattleParty = createParty(param1,param3,param4,param5,param7,param8,param9);
         if(!param2)
         {
            param2 = param4 + "+" + _loc12_.numMembers + "+" + param6.id;
         }
         var _loc11_:BattleEntity = createEntity(param6,param2,-1,-1,_loc12_);
         _loc11_.enabled = false;
         _loc12_.addMember(_loc11_);
         var _loc10_:BattleFacing = this.def.getDeploymentFacing(param5);
         _loc11_.facing = _loc10_;
         return _loc11_;
      }
      
      public function addRemoteParty(param1:String, param2:String, param3:String, param4:String, param5:IEntityListDef, param6:int, param7:Boolean) : void
      {
         var _loc9_:int = 0;
         var _loc8_:IEntityDef = null;
         _loc9_ = 0;
         while(_loc9_ < param5.numEntityDefs)
         {
            _loc8_ = param5.getEntityDef(_loc9_);
            if(!_loc8_)
            {
               throw new IllegalOperationError("Found null def for party member " + _loc9_ + ", party=" + param5);
            }
            addPartyMember(param1,null,param2,param3,param4,_loc8_,BattlePartyType.REMOTE,param6,param7);
            _loc9_++;
         }
      }

      // Offline vs-AI: add a CPU-controlled party that is fully deployed up front (no human deploy
      // step). Faithful sibling of addRemoteParty() above, but with BattlePartyType.AI. NOTE the
      // deploy phase (BattleStateDeploy) only auto-deploys LOCAL parties and waits on REMOTE ones --
      // it does NOTHING for AI parties -- so we must position the members ourselves here, the same
      // way scene-spawned AI is positioned before deployment. We reuse the engine's own
      // autoDeployPartyById (places each member on the party's deployment-area tiles: setPos +
      // deploymentReady), then mark the party deployed so the deploy phase skips it. Pass a DISTINCT
      // team (e.g. "ai") so mirrored, identical entity defs don't collide with the player's ids
      // (addPartyMember namespaces ids by team).
      public function addAiParty(param1:String, param2:String, param3:String, param4:String, param5:IEntityListDef, param6:int, param7:Boolean) : void
      {
         var _loc8_:int = 0;
         var _loc9_:IEntityDef = null;
         _loc8_ = 0;
         while(_loc8_ < param5.numEntityDefs)
         {
            _loc9_ = param5.getEntityDef(_loc8_);
            if(!_loc9_)
            {
               throw new IllegalOperationError("Found null def for AI party member " + _loc8_ + ", party=" + param5);
            }
            addPartyMember(param1,null,param2,param3,param4,_loc9_,BattlePartyType.AI,param6,param7);
            _loc8_++;
         }
         autoDeployPartyById(param2);
         var _loc10_:BattleParty = partiesById[param2];
         if(_loc10_)
         {
            _loc10_.deployed = true;
         }
      }

      private function spawnerTagsOk(param1:BattleSpawnerDef, param2:String) : Boolean
      {
         if(spawn_tags_dict && param1.tags)
         {
            if(!(param1.tags in spawn_tags_dict))
            {
               if(param1.tags != param2)
               {
                  return false;
               }
            }
         }
         if(param2 && param1.tags != param2)
         {
            return false;
         }
         return true;
      }
      
      private function spawnEntity(param1:BattleSpawnerDef, param2:IEntityDef) : int
      {
         var _loc4_:int = 0;
         var _loc7_:int = 0;
         var _loc6_:Stat = null;
         var _loc3_:Stat = null;
         if(!param2)
         {
            return 0;
         }
         var _loc5_:BattleEntity = null;
         if(param1.prop == true)
         {
            _loc5_ = createEntity(param2,param1.team + "+" + param2.id,-1,-1,null);
         }
         else
         {
            _loc5_ = addPartyMember(param1.team,null,param1.team,param1.team,null,param2,BattlePartyType.AI,0,param1.isAlly);
         }
         if(_loc5_)
         {
            _loc4_ = _loc5_.stats.getValue(StatType.RANK);
            _loc5_.enabled = true;
            _loc5_.setPos(param1.location.x,param1.location.y);
            _loc5_.facing = param1.facing;
            if(param1.stats)
            {
               _loc7_ = 0;
               while(_loc7_ < param1.stats.numStats)
               {
                  _loc6_ = param1.stats.getStatByIndex(_loc7_);
                  _loc3_ = _loc5_.stats.getStat(_loc6_.type,false);
                  if(!_loc3_)
                  {
                     _loc5_.stats.addStat(_loc6_.type,_loc6_.base);
                  }
                  else
                  {
                     _loc3_.base = _loc6_.value;
                  }
                  _loc7_++;
               }
            }
            _loc5_.deploymentReady = true;
            return _loc4_;
         }
         return 0;
      }
      
      public function spawn(param1:String, param2:String) : void
      {
         var _loc8_:IEntityDef = null;
         var _loc6_:IEntityClassDef = null;
         var _loc7_:EntityDef = null;
         var _loc3_:int = 0;
         for each(var _loc5_ in def.spawners)
         {
            if(!(!shouldSpawnAi && !_loc5_.prop))
            {
               if(!spawnerTagsOk(_loc5_,param2))
               {
                  logger.info("BattleBoard.spawn: skipping tagged spawner " + _loc5_);
               }
               else
               {
                  _loc8_ = null;
                  if(_loc5_.character && scene.context.spawnables)
                  {
                     _loc8_ = scene.context.spawnables.getEntityDefById(_loc5_.character);
                     if(!_loc8_)
                     {
                        logger.error("BattleBoard.spawn: no such entity def: " + _loc5_.character);
                     }
                  }
                  else if(_loc5_.entityClassId && scene.context.classes)
                  {
                     _loc6_ = scene.context.classes.fetch(_loc5_.entityClassId);
                     if(!_loc6_)
                     {
                        logger.error("BattleBoard.spawn: no such class: " + _loc5_.entityClassId);
                        continue;
                     }
                     _loc7_ = new EntityDef(scene.context.locale);
                     _loc7_.entityClass = _loc6_;
                     _loc7_.id = _loc6_.id;
                     _loc7_.setupClassAbilities(scene.context.abilities);
                     _loc7_.applyClassStats(1);
                     _loc8_ = _loc7_;
                  }
                  _loc3_ += spawnEntity(_loc5_,_loc8_);
               }
            }
         }
         if(bucket)
         {
            spawnFromBucket(_loc3_,param1);
         }
         for each(var _loc4_ in parties)
         {
            if(_loc4_.type == BattlePartyType.AI)
            {
               _loc4_.deployed = true;
            }
         }
      }
      
      private function pickFromBucket(param1:SagaBucket, param2:int) : IEntityDef
      {
         var _loc8_:IEntityDef = null;
         var _loc3_:* = null;
         var _loc6_:Saga = scene.context.saga;
         var _loc5_:int = 0;
         for each(_loc3_ in param1.ents)
         {
            _loc8_ = _loc6_.def.cast.getEntityDefById(_loc3_);
            if(!_loc8_)
            {
               logger.error("Invalid bucket entity [" + _loc3_ + "]");
            }
            else if(_loc8_.stats.getValue(StatType.RANK) <= param2)
            {
               _loc5_++;
            }
         }
         if(_loc5_ <= 0)
         {
            return null;
         }
         var _loc7_:int = MathUtil.randomInt(0,_loc5_ - 1);
         var _loc4_:int = 0;
         for each(_loc3_ in param1.ents)
         {
            _loc8_ = _loc6_.def.cast.getEntityDefById(_loc3_);
            if(_loc8_ && _loc8_.stats.getValue(StatType.RANK) <= param2)
            {
               if(_loc4_ == _loc7_)
               {
                  return _loc8_;
               }
               _loc4_++;
            }
         }
         return null;
      }
      
      private function spawnFromBucket(param1:int, param2:String) : void
      {
         var _loc4_:int = 0;
         var _loc3_:String = null;
         var _loc10_:IEntityDef = null;
         var _loc6_:Boolean = false;
         var _loc5_:BattleEntity = null;
         var _loc7_:int = 0;
         var _loc8_:Saga = scene.context.saga;
         if(!_loc8_)
         {
            return;
         }
         var _loc9_:SagaBucket = _loc8_.def.buckets.getSagaBucket(bucket);
         if(!_loc9_)
         {
            return;
         }
         while(param1 < bucket_quota)
         {
            _loc4_ = MathUtil.randomInt(0,_loc9_.ents.length - 1);
            _loc3_ = _loc9_.ents[_loc4_];
            _loc10_ = pickFromBucket(_loc9_,bucket_quota - param1);
            _loc5_ = addPartyMember("npc",null,"npc","npc",param2,_loc10_,BattlePartyType.AI,0,_loc6_);
            (_loc5_.party as BattleParty).changeDeployment(param2);
            _loc7_ = _loc5_.stats.getValue(StatType.RANK);
            param1 += _loc7_;
         }
         autoDeployPartyById("npc");
      }
      
      protected function addBoardTriggers() : void
      {
         var _loc1_:Tile = null;
         var _loc2_:BattleBoardTriggerDef = null;
         var _loc4_:BattleAbilityDef = null;
         if(def.triggerDefManager == null)
         {
            return;
         }
         for each(var _loc3_ in def.triggers)
         {
            _loc1_ = tiles.getTile(_loc3_.location.x,_loc3_.location.y);
            if(_loc1_ != null)
            {
               _loc2_ = def.triggerDefManager.getDef(_loc3_.id);
               if(_loc2_ != null)
               {
                  _loc4_ = this.abilityManager.factory.fetchBattleAbilityDef(_loc2_.ability);
                  if(_loc4_ != null)
                  {
                     tiles.addAbilityBasedTrigger(_loc1_.rect,_loc4_,_loc2_.pulse);
                  }
               }
            }
         }
      }
      
      public function get numParties() : int
      {
         return parties.length;
      }
      
      public function getParty(param1:int) : IBattleParty
      {
         return parties[param1];
      }
      
      public function getPartyById(param1:String) : IBattleParty
      {
         return partiesById[param1];
      }
      
      public function getPartyIndex(param1:IBattleParty) : int
      {
         return parties.indexOf(param1);
      }
      
      public function get entities() : Dictionary
      {
         return _entities;
      }
      
      public function get logger() : ILogger
      {
         return _logger;
      }
      
      public function get tiles() : Tiles
      {
         return _tiles;
      }
      
      public function get triggers() : IBattleBoardTriggers
      {
         return _triggers;
      }
      
      public function getEntity(param1:String) : IBattleEntity
      {
         return _entities[param1];
      }
      
      public function get abilityManager() : BattleAbilityManager
      {
         return _abilityManager;
      }
      
      public function autoDeployPartyById(param1:String) : void
      {
         var _loc5_:int = 0;
         var _loc2_:IBattleEntity = null;
         var _loc4_:IBattleParty = getPartyById(param1);
         var _loc3_:BattleDeploymentArea = def.getDeploymentAreaById(_loc4_.deployment);
         if(_loc3_)
         {
         }
         if(!_loc3_)
         {
            logger.error("BattleSim.autoDeploy Cannot autodeploy to non-existent area: " + _loc4_.deployment);
         }
         else
         {
            _loc5_ = 0;
            while(_loc5_ < _loc4_.numMembers)
            {
               _loc2_ = _loc4_.getMember(_loc5_);
               if(!_loc2_.deploymentReady)
               {
                  autoDeployCharacter(_loc2_,_loc3_);
               }
               _loc5_++;
            }
         }
      }
      
      public function autoDeployCharacter(param1:IBattleEntity, param2:BattleDeploymentArea) : void
      {
         var _loc5_:TileRect = param2.area.rect;
         var _loc3_:Point = def.walkableTiles.rect.center;
         param2.area.sortByRow(TileLocation.fetch(_loc3_.x,_loc3_.y),false);
         for each(var _loc4_ in param2.area.sorted)
         {
            if(attemptDeploy(param1,param2.area,_loc4_))
            {
               return;
            }
         }
         logger.error("Failed to autoDeployCharacter in deployment: " + param2);
      }
      
      public function attemptDeploy(param1:IBattleEntity, param2:TileLocationArea, param3:TileLocation) : Boolean
      {
         var _loc7_:int = 0;
         var _loc6_:int = 0;
         var _loc4_:TileLocation = null;
         if(!param3)
         {
            return false;
         }
         var _loc5_:Boolean = findAllRectIntersectionEntities(param3.x,param3.y,param1.width,param1.length,param1,null);
         if(_loc5_)
         {
            return false;
         }
         _loc7_ = 0;
         while(_loc7_ < param1.width)
         {
            _loc6_ = 0;
            while(_loc6_ < param1.length)
            {
               _loc4_ = TileLocation.fetch(param3.x + _loc7_,param3.y + _loc6_);
               if(!param2.hasTile(_loc4_))
               {
                  return false;
               }
               _loc6_++;
            }
            _loc7_++;
         }
         param1.setPos(param3.x,param3.y);
         param1.deploymentReady = true;
         return true;
      }
      
      public function get def() : BattleBoardDef
      {
         return _def;
      }
      
      public function set def(param1:BattleBoardDef) : void
      {
         _def = param1;
      }
      
      public function get fake() : Boolean
      {
         return _fake;
      }
      
      public function set fake(param1:Boolean) : void
      {
         if(_fake == param1)
         {
            return;
         }
         _fake = param1;
         abilityManager.faking = _fake;
         for each(var _loc2_ in entities)
         {
            _loc2_.fake = _fake;
         }
      }
      
      public function update(param1:int) : void
      {
         updating = true;
         for each(var _loc3_ in entities)
         {
            _loc3_.update(param1);
         }
         for each(var _loc2_ in vfxs)
         {
            _loc2_.update(param1);
         }
         updating = false;
      }
      
      public function get boardSetup() : Boolean
      {
         return _boardSetup;
      }
      
      public function set boardSetup(param1:Boolean) : void
      {
         if(_boardSetup != param1)
         {
            _boardSetup = param1;
            dispatchEvent(new BattleBoardEvent("BattleBoardEvent.BOARDSETUP"));
         }
      }
      
      public function get fsm() : BattleFsm
      {
         return sim.fsm;
      }
      
      public function get resman() : ResourceManager
      {
         return _resman;
      }
      
      public function addVfxSequence(param1:VfxSequence) : void
      {
         if(updating)
         {
            throw new IllegalOperationError("Cannot add vfx sequence during update - yet");
         }
         vfxs.push(param1);
      }
      
      public function removeVfxSequence(param1:VfxSequence) : void
      {
         if(updating)
         {
            throw new IllegalOperationError("Cannot remove vfx sequence during update - yet");
         }
         var _loc2_:int = vfxs.indexOf(param1);
         if(_loc2_ >= 0)
         {
            vfxs.splice(_loc2_,1);
         }
      }
      
      private function triggersRemovedHandler(param1:BattleBoardTriggersEvent) : void
      {
         var _loc3_:BattleBoardTrigger = param1.trigger;
         for each(var _loc2_ in _loc3_.vfxs)
         {
            removeVfxSequence(_loc2_);
         }
      }
      
      private function triggersAddedHandler(param1:BattleBoardTriggersEvent) : void
      {
         var _loc3_:BattleBoardTrigger = param1.trigger;
         for each(var _loc2_ in _loc3_.vfxs)
         {
            addVfxSequence(_loc2_);
         }
      }
      
      private function expireDeadEntitiesEffects() : void
      {
         for each(var _loc1_ in entities)
         {
            _loc1_.expireDeadEntitiesEffects();
         }
      }
      
      public function get spawn_tags() : String
      {
         return _spawn_tags;
      }
      
      public function set spawn_tags(param1:String) : void
      {
         var _loc3_:Array = null;
         _spawn_tags = param1;
         spawn_tags_dict = new Dictionary();
         if(_spawn_tags)
         {
            _loc3_ = _spawn_tags.split(" ");
            for each(var _loc2_ in _loc3_)
            {
               spawn_tags_dict[_loc3_] = true;
            }
         }
      }
   }
}

