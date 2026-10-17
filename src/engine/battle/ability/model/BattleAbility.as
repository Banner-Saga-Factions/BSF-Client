package engine.battle.ability.model
{
   import engine.battle.ability.def.BattleAbilityDef;
   import engine.battle.ability.def.BattleAbilityRotationRule;
   import engine.battle.ability.def.BattleAbilityTargetRotationRule;
   import engine.battle.ability.def.BattleAbilityTargetRule;
   import engine.battle.ability.effect.def.EffectDefConditions;
   import engine.battle.ability.effect.def.IEffectDef;
   import engine.battle.ability.effect.model.Effect;
   import engine.battle.ability.effect.model.EffectPhase;
   import engine.battle.ability.phantasm.model.ChainPhantasms;
   import engine.battle.ability.phantasm.model.ChainPhantasmsEvent;
   import engine.battle.board.model.IBattleEntity;
   import engine.battle.fsm.BattleMove;
   import engine.stat.def.StatType;
   import engine.stat.model.Stat;
   import engine.tile.Tile;
   import flash.errors.IllegalOperationError;
   import flash.events.EventDispatcher;
   import flash.utils.Dictionary;
   
   public class BattleAbility extends EventDispatcher implements IBattleAbility
   {
      
      private var _parent:IBattleAbility;
      
      private var _def:BattleAbilityDef;
      
      private var callback:Function;
      
      private var _caster:IBattleEntity;
      
      public var chains:Vector.<ChainPhantasms> = new Vector.<ChainPhantasms>();
      
      public var effects:Vector.<Effect> = new Vector.<Effect>();
      
      private var _executed:Boolean;
      
      private var _executing:Boolean;
      
      private var _completed:Boolean;
      
      private var abilityPreCompletionTriggered:Boolean;
      
      private var abilityPostCompletionTriggered:Boolean;
      
      private var children:Vector.<BattleAbility> = new Vector.<BattleAbility>();
      
      private var tags:Dictionary = new Dictionary();
      
      private var _targetSet:BattleTargetSet;
      
      private var _manager:BattleAbilityManager;
      
      public var id:int;
      
      private var targetsAffected:int = 0;
      
      private var _fake:Boolean;
      
      private var _executedId:int;
      
      private var _blockedComplete:int = 0;
      
      private var _finalCompleted:Boolean;
      
      public function BattleAbility(param1:IBattleEntity, param2:BattleAbilityDef, param3:BattleAbilityManager)
      {
         super();
         if(param1 == null)
         {
            param3.logger.error("Must have a caster for battle ability " + param2);
            throw new IllegalOperationError("no caster");
         }
         this.caster = param1;
         this.id = param3.nextId;
         this._def = param2;
         this._manager = param3;
         _targetSet = new BattleTargetSet(this);
         if(_manager.faking)
         {
            _fake = true;
         }
      }
      
      public static function getStatChange(param1:BattleAbilityDef, param2:IBattleEntity, param3:StatType, param4:StatChangeData, param5:IBattleEntity, param6:BattleMove) : Boolean
      {
         var _loc9_:Tile = null;
         var _loc12_:BattleAbility = null;
         var _loc8_:int = 0;
         var _loc11_:int = 0;
         var _loc7_:BattleAbilityValidation = BattleAbilityValidation.validate(param1 as BattleAbilityDef,param2,param6,param5,null,false,false);
         var _loc10_:int = -1;
         if(_loc7_ == BattleAbilityValidation.OK && param5.stats.getValue(param3) > 0)
         {
            _loc9_ = param2.tile;
            try
            {
               param2.suppressMoveEvents = true;
               if(param6)
               {
                  param2.setPos(param6.last.x,param6.last.y);
               }
               param2.board.fake = true;
               _loc12_ = new BattleAbility(param2,param1,param2.board.abilityManager);
               _loc12_.targetSet.setTarget(param5);
               _loc8_ = int(param5.stats.getValue(param3));
               _loc12_.execute(null);
               param4.missChance = param5.stats.getValue(StatType.FAKE_MISS_CHANCE);
               _loc11_ = int(param5.stats.getValue(param3));
               _loc10_ = _loc8_ - _loc11_;
            }
            catch(e:Error)
            {
               // [Inference] BSF-Client #31: the original returned here without undoing what the
               // try block had set up, so one failed imagined move left the whole board in
               // pretend mode, the unit standing on the imagined tile, and its move events
               // muted. Undo the same three things the success path below undoes.
               param2.board.fake = false;
               if(_loc9_)
               {
                  param2.setPos(_loc9_.x,_loc9_.y);
               }
               param2.suppressMoveEvents = false;
               param2.board.logger.error("Something went wrong while faking " + param3 + " with " + param1 + ": " + e.getStackTrace());
               return false;
            }
            param2.board.fake = false;
            param2.setPos(_loc9_.x,_loc9_.y);
            param2.suppressMoveEvents = false;
            param4.amount = _loc10_;
            return true;
         }
         return false;
      }
      
      public function set targetSet(param1:BattleTargetSet) : void
      {
         _targetSet = param1;
      }
      
      public function get root() : IBattleAbility
      {
         if(parent)
         {
            return parent.root;
         }
         return this;
      }
      
      private function get debugCasterId() : String
      {
         return caster ? caster.id : "null";
      }
      
      override public function toString() : String
      {
         return "[" + executedId + " " + debugCasterId + "->" + targetSet.debugIds + " " + def.id + "/" + def.level + "]";
      }
      
      private function executeTiles() : void
      {
         var _loc6_:Boolean = false;
         var _loc2_:Boolean = false;
         var _loc4_:Boolean = false;
         var _loc3_:Effect = null;
         var _loc1_:BattleAbilityValidation = null;
         var _loc7_:int = 0;
         for each(var _loc5_ in targetSet.tiles)
         {
            _loc2_ = shouldAllowRotation();
            _loc4_ = shouldAllowTargetRotation();
            for each(var _loc8_ in def.effects)
            {
               if(checkEffectConditions(_loc8_))
               {
                  _loc1_ = BattleAbilityValidation.validate(def,caster,null,targetSet.baseTarget,_loc5_,false,false);
                  if(_loc1_ == BattleAbilityValidation.OK)
                  {
                     if(!_loc6_)
                     {
                        _loc6_ = true;
                        targetsAffected = targetsAffected + 1;
                     }
                     _loc3_ = new Effect(this,_loc8_,targetSet.baseTarget,_loc5_);
                     executeEffect(_loc3_,_loc7_,_loc2_,_loc4_);
                  }
               }
            }
            _loc7_ += def.targetDelay;
         }
      }
      
      private function shouldAllowRotation() : Boolean
      {
         switch(def.rotationRule)
         {
            case BattleAbilityRotationRule.FIRST_TARGET:
               return targetsAffected == 0;
            case BattleAbilityRotationRule.ALL_TARGETS:
               return true;
            case BattleAbilityRotationRule.NONE:
               return false;
            default:
               return false;
         }
      }
      
      private function shouldAllowTargetRotation() : Boolean
      {
         switch(def.targetRotationRule)
         {
            case BattleAbilityTargetRotationRule.FACE_CASTER:
               return true;
            case BattleAbilityTargetRotationRule.NONE:
               return false;
            default:
               return false;
         }
      }
      
      private function executeTargetEffectDef(param1:IBattleEntity, param2:IEffectDef, param3:int, param4:Boolean, param5:Boolean, param6:Boolean, param7:BattleAbilityRetargetInfo) : Boolean
      {
         var _loc9_:Effect = null;
         var _loc8_:BattleAbilityValidation = null;
         if(!fake && !manager.faking)
         {
            manager.logger.debug("BattleAbility.executeTargetEffectDef() " + param1 + " " + param2);
         }
         if(!checkEffectConditions(param2))
         {
            return false;
         }
         if(param7)
         {
            param1 = param7.target;
         }
         var _loc10_:Tile = targetSet.baseTile;
         if(param6)
         {
            _loc8_ = BattleAbilityValidation.validate(def,caster,null,param1,_loc10_,false,false);
         }
         if(!param6 || _loc8_ == BattleAbilityValidation.OK)
         {
            _loc9_ = new Effect(this,param2,param1,_loc10_);
            _loc9_.waitForAbility = param7 ? param7.insert : null;
            executeEffect(_loc9_,param3,param4,param5);
            return true;
         }
         if(!fake && !manager.faking)
         {
            manager.logger.debug("BattleAbility.executeTargetEffectDef() could not validate effect " + this.def.id + "," + param2.name + " for target " + param1.id + " validation=" + _loc8_);
         }
         return false;
      }
      
      private function executeTargets() : void
      {
         var _loc9_:* = null;
         var _loc5_:Boolean = false;
         var _loc1_:Boolean = false;
         var _loc2_:Boolean = false;
         var _loc8_:BattleAbilityRetargetInfo = null;
         var _loc7_:Boolean = false;
         var _loc3_:Tile = targetSet.baseTile;
         var _loc6_:int = 0;
         for each(_loc9_ in def.effects)
         {
            if(_loc9_.targetCaster)
            {
               executeTargetEffectDef(caster,_loc9_,_loc6_,false,false,false,null);
            }
         }
         for each(var _loc4_ in targetSet.targets)
         {
            _loc1_ = shouldAllowRotation();
            _loc2_ = shouldAllowTargetRotation();
            _loc8_ = _loc4_.effects.onAbilityExecutingOnTarget(this);
            if(_loc8_)
            {
               if(!fake && !manager.faking)
               {
                  manager.logger.debug("BattleAbility.executeTargets() " + this + " retargeted " + _loc4_ + " to " + _loc8_);
               }
            }
            for each(_loc9_ in def.effects)
            {
               if(!_loc9_.targetCaster)
               {
                  _loc7_ = _loc8_ == null;
                  if(executeTargetEffectDef(_loc4_,_loc9_,_loc6_,_loc1_,_loc2_,_loc7_,_loc8_))
                  {
                     if(!_loc5_)
                     {
                        _loc5_ = true;
                        targetsAffected = targetsAffected + 1;
                     }
                  }
               }
            }
            _loc6_ += def.targetDelay;
         }
      }
      
      public function checkCosts(param1:Boolean = false) : Boolean
      {
         var _loc5_:int = 0;
         var _loc4_:Stat = null;
         var _loc3_:Boolean = true;
         if(def.horn)
         {
            if(caster.party.hornSize < def.horn)
            {
               if(!param1 && !fake && !manager.faking)
               {
                  manager.logger.error("Not enough HORN for " + this);
               }
               _loc3_ = false;
            }
         }
         var _loc2_:int = def.costs.numStats;
         _loc5_ = 0;
         while(_loc5_ < _loc2_)
         {
            _loc4_ = def.costs.getStatByIndex(_loc5_);
            if(_loc4_.value > caster.stats.getValue(_loc4_.type))
            {
               if(!param1 && !fake && !manager.faking)
               {
                  manager.logger.error("Not enough " + _loc4_.type + " for " + this);
               }
               _loc3_ = false;
            }
            _loc5_++;
         }
         return _loc3_;
      }
      
      private function deductCosts() : Boolean
      {
         var _loc1_:int = 0;
         var _loc3_:int = 0;
         var _loc2_:Stat = null;
         if(!checkCosts())
         {
            return false;
         }
         if(!fake && !manager.faking)
         {
            if(def.horn)
            {
               caster.party.hornSize -= def.horn;
            }
            _loc1_ = def.costs.numStats;
            _loc3_ = 0;
            while(_loc3_ < _loc1_)
            {
               _loc2_ = def.costs.getStatByIndex(_loc3_);
               caster.stats.getStat(_loc2_.type).base = caster.stats.getStat(_loc2_.type).base - _loc2_.value;
               _loc3_++;
            }
         }
         return true;
      }
      
      public function execute(param1:Function) : void
      {
         if(executed || executing)
         {
            throw new IllegalOperationError("no, no, no");
         }
         if(!_manager.enabled)
         {
            return;
         }
         var _loc2_:int = manager.nextExecutedId;
         if(_executedId != 0 && _loc2_ != _executedId)
         {
            manager.logger.error("DIVERGENCE Ability: " + this + ", should be id " + _executedId);
         }
         _executedId = _loc2_;
         executing = true;
         if(!deductCosts())
         {
            manager.logger.error("Attempt to execute ability without being able to pay the costs " + this);
            checkCompletion();
            return;
         }
         this.callback = param1;
         if(targetSet.targets.length == 0)
         {
            targetSet.setTarget(caster);
         }
         if(!fake && !manager.faking)
         {
            manager.logger.debug("BattleAbility.execute() " + this);
         }
         if(def.targetRule == BattleAbilityTargetRule.TILE_EMPTY || def.targetRule == BattleAbilityTargetRule.TILE_ANY)
         {
            executeTiles();
         }
         else
         {
            executeTargets();
         }
         executing = false;
         executed = true;
         checkCompletion();
      }
      
      public function addChildAbility(param1:IBattleAbility) : void
      {
         if(param1 == this)
         {
            throw new IllegalOperationError("epic failure of parenting");
         }
         if(!_manager.enabled)
         {
            return;
         }
         param1.parent = this;
         children.push(param1);
         param1.execute(null);
      }
      
      private function checkEffectConditions(param1:IEffectDef) : Boolean
      {
         var _loc2_:Effect = null;
         for each(var _loc3_ in param1.conditions)
         {
            if(_loc3_.other)
            {
               _loc2_ = getEffectByName(_loc3_.other);
               if(!_loc2_)
               {
                  return false;
               }
               if(!_loc3_.isResultSatisfactory(_loc2_.result))
               {
                  return false;
               }
            }
            if(_loc3_.minLevel > def.level)
            {
               return false;
            }
         }
         return true;
      }
      
      public function getEffectByName(param1:String) : Effect
      {
         for each(var _loc2_ in effects)
         {
            if(_loc2_.def.name == param1)
            {
               return _loc2_;
            }
         }
         return null;
      }
      
      public function getEffectByDef(param1:IEffectDef) : Effect
      {
         for each(var _loc2_ in effects)
         {
            if(_loc2_.def == param1)
            {
               return _loc2_;
            }
         }
         return null;
      }
      
      public function executeEffect(param1:Effect, param2:int, param3:Boolean, param4:Boolean) : void
      {
         var _loc5_:ChainPhantasms = null;
         effects.push(param1);
         param1.execute();
         if(param1.def.phantasms != null)
         {
            if(!fake && !manager.faking)
            {
               _loc5_ = caster.createChainForEffect(param1) as ChainPhantasms;
               if(_loc5_)
               {
                  chains.push(_loc5_);
                  _loc5_.addEventListener("ChainPhantasmsEvent.ENDED",phantasmsEndedHandler);
                  _loc5_.addEventListener("ChainPhantasmsEvent.APPLIED",phantasmAppliedHandler);
                  _loc5_.start(param2,param3,param4);
               }
            }
         }
         if(!_loc5_)
         {
            param1.apply();
            param1.phase = EffectPhase.COMPLETED;
         }
      }
      
      protected function phantasmAppliedHandler(param1:ChainPhantasmsEvent) : void
      {
         param1.chain.effect.apply();
         handlePhantasmsEnded(param1.chain);
      }
      
      private function handlePhantasmsEnded(param1:ChainPhantasms) : void
      {
         var _loc2_:int = 0;
         if(param1.ended)
         {
            param1.removeEventListener("ChainPhantasmsEvent.ENDED",phantasmsEndedHandler);
            param1.removeEventListener("ChainPhantasmsEvent.APPLIED",phantasmAppliedHandler);
            _loc2_ = chains.indexOf(param1);
            if(_loc2_ >= 0)
            {
               chains.splice(_loc2_,1);
            }
            param1.effect.phase = EffectPhase.COMPLETED;
            param1.cleanup();
            checkCompletion();
         }
      }
      
      protected function phantasmsEndedHandler(param1:ChainPhantasmsEvent) : void
      {
         handlePhantasmsEnded(param1.chain);
      }
      
      private function checkChildCompletion() : Boolean
      {
         for each(var _loc1_ in children)
         {
            if(!_loc1_.completed)
            {
               manager.logger.debug("BattleAbility.checkCompletion checkChildCompletion " + this + " WAITING CHILD " + _loc1_);
               return false;
            }
         }
         return true;
      }
      
      public function checkCompletion() : void
      {
         if(completed)
         {
            if(!fake && !manager.faking)
            {
            }
            return;
         }
         if(!executed)
         {
            if(!fake && !manager.faking)
            {
            }
            return;
         }
         if(chains.length > 0)
         {
            if(!fake && !manager.faking)
            {
            }
            return;
         }
         if(blockedComplete)
         {
            return;
         }
         for each(var _loc1_ in effects)
         {
            if(_loc1_.isBlockedComplete)
            {
               if(!fake && !manager.faking)
               {
                  manager.logger.debug("BattleAbility.checkCompletion FALSE " + this + " EFFECT BLOCKED " + _loc1_);
               }
               return;
            }
         }
         for each(var _loc2_ in chains)
         {
            if(!_loc2_.ended)
            {
               if(!fake && !manager.faking)
               {
               }
               return;
            }
         }
         if(!checkChildCompletion())
         {
            if(!fake && !manager.faking)
            {
            }
            return;
         }
         if(!abilityPreCompletionTriggered)
         {
            abilityPreCompletionTriggered = true;
            dispatchEvent(new BattleAbilityEvent("BattleAbilityEvent.ABILITY_PRE_COMPLETE",this));
            manager.onAbilityPreComplete(this);
            if(!checkChildCompletion())
            {
               if(!fake && !manager.faking)
               {
               }
               return;
            }
         }
         completed = true;
         if(!fake && !manager.faking)
         {
            manager.logger.debug("BattleAbility.checkCompletion COMPLETED " + this + ", children=" + children.length);
         }
         if(parent)
         {
            parent.checkCompletion();
         }
         if(completed)
         {
            handlePostComplete();
         }
      }
      
      private function handlePostComplete() : void
      {
         if(!completed)
         {
            return;
         }
         if(!abilityPostCompletionTriggered)
         {
            abilityPostCompletionTriggered = true;
            dispatchEvent(new BattleAbilityEvent("BattleAbilityEvent.ABILITY_POST_COMPLETE",this));
            manager.onAbilityPostComplete(this);
            if(!checkChildCompletion())
            {
               completed = false;
               return;
            }
         }
         for each(var _loc1_ in children)
         {
            _loc1_.handlePostComplete();
            if(!_loc1_.completed)
            {
               completed = false;
            }
         }
         if(!completed)
         {
            return;
         }
         if(!finalCompleted)
         {
            dispatchEvent(new BattleAbilityEvent("BattleAbilityEvent.ABILITY_AND_CHILDREN_COMPLETE",this));
            manager.onAbilityAndChildrenComplete(this);
            setFinalCompleted();
         }
      }
      
      public function onEffectPhaseChange(param1:Effect) : void
      {
         for each(var _loc2_ in chains)
         {
            _loc2_.onEffectPhaseChange(param1);
         }
      }
      
      public function get executed() : Boolean
      {
         return _executed;
      }
      
      public function set executed(param1:Boolean) : void
      {
         _executed = param1;
      }
      
      public function get executing() : Boolean
      {
         return _executing;
      }
      
      public function set executing(param1:Boolean) : void
      {
         if(_executing == param1)
         {
            return;
         }
         _executing = param1;
         dispatchEvent(new BattleAbilityEvent("BattleAbilityEvent.EXECUTING",this));
         manager.onAbilityExecuting(this);
      }
      
      public function get completed() : Boolean
      {
         return _completed;
      }
      
      public function set completed(param1:Boolean) : void
      {
         _completed = param1;
      }
      
      public function get finalCompleted() : Boolean
      {
         return _finalCompleted;
      }
      
      public function setFinalCompleted() : void
      {
         if(finalCompleted)
         {
            return;
         }
         _finalCompleted = true;
         if(callback != null)
         {
            callback(this);
            callback = null;
         }
         dispatchEvent(new BattleAbilityEvent("BattleAbilityEvent.FINAL_COMPLETE",this));
         manager.onAbilityFinalComplete(this);
      }
      
      public function get caster() : IBattleEntity
      {
         return _caster;
      }
      
      public function set caster(param1:IBattleEntity) : void
      {
         _caster = param1;
      }
      
      public function get def() : BattleAbilityDef
      {
         return _def;
      }
      
      public function get targetSet() : BattleTargetSet
      {
         return _targetSet;
      }
      
      public function get parent() : IBattleAbility
      {
         return _parent;
      }
      
      public function set parent(param1:IBattleAbility) : void
      {
         _parent = param1;
      }
      
      public function get manager() : BattleAbilityManager
      {
         return _manager;
      }
      
      public function get fake() : Boolean
      {
         return _fake;
      }
      
      public function get executedId() : int
      {
         return _executedId;
      }
      
      public function internalSetexecutedId(param1:int) : void
      {
         _executedId = param1;
      }
      
      public function removeAllEffects() : void
      {
         for each(var _loc1_ in effects)
         {
            if(_loc1_.phase != EffectPhase.REMOVED)
            {
               _loc1_.remove();
            }
         }
      }
      
      public function onEffectUnblocked(param1:Effect) : void
      {
         checkCompletion();
      }
      
      public function get isBlockedComplete() : Boolean
      {
         return _blockedComplete > 0;
      }
      
      public function get blockedComplete() : int
      {
         return _blockedComplete;
      }
      
      public function set blockedComplete(param1:int) : void
      {
         if(_blockedComplete == param1)
         {
            return;
         }
         _blockedComplete = param1;
         if(_blockedComplete == 0)
         {
            checkCompletion();
         }
      }
      
      public function blockComplete() : void
      {
         blockedComplete = blockedComplete + 1;
      }
      
      public function unblockComplete() : void
      {
         blockedComplete = blockedComplete - 1;
      }
   }
}

