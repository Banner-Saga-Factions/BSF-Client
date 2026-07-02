package engine.battle.fsm.aimodule
{
   import engine.ability.def.AbilityDefLevel;
   import engine.battle.ability.def.BattleAbilityDef;
   import engine.battle.ability.def.BattleAbilityDefLevels;
   import engine.battle.ability.def.BattleAbilityTag;
   import engine.battle.entity.model.BattleEntity;
   import engine.battle.fsm.BattleFsm;
   import engine.battle.fsm.BattleMove;
   import engine.battle.fsm.state.BattleStateTurnAi;
   import engine.stat.def.StatType;
   import engine.tile.Tile;
   
   public class AiModuleBase
   {
      
      public var ss:BattleStateTurnAi;
      
      public var battleFsm:BattleFsm;
      
      public var caster:BattleEntity;
      
      public var enemies:Vector.<BattleEntity> = new Vector.<BattleEntity>();
      
      public var friends:Vector.<BattleEntity> = new Vector.<BattleEntity>();
      
      public var isRanged:Boolean = false;
      
      public var atkStr:AbilityDefLevel;
      
      public var atkArm:AbilityDefLevel;
      
      public function AiModuleBase(param1:BattleStateTurnAi)
      {
         super();
         battleFsm = param1.battleFsm;
         ss = param1;
         caster = battleFsm.turn.entity as BattleEntity;
         buildEnemyArray();
         var _loc2_:BattleAbilityDefLevels = battleFsm.turn.entity.def.attacks as BattleAbilityDefLevels;
         if(_loc2_)
         {
            atkStr = _loc2_.getFirstAbilityByTag(BattleAbilityTag.ATTACK_STR);
            atkArm = _loc2_.getFirstAbilityByTag(BattleAbilityTag.ATTACK_ARM);
         }
         // [Inference] BSF-Client #12: atkStr/atkArm are null for a unit lacking that attack type
         // (a Shieldbanger has no strength attack). The decompiled code derefs atkStr.id/atkArm.id
         // unconditionally and crashes (#1009) the moment this AI controls such a unit. Downstream
         // code already null-guards atkStr/atkArm (AiModuleDredge.performMove, AiPlan), so leaving
         // them null is safe -- only this isRanged bow-check needed guarding; a null attack simply
         // is not a bow. See "A-0.log-ai test2.txt".
         isRanged = (atkStr != null && atkStr.id == "abl_bow_str") || (atkArm != null && atkArm.id == "abl_bow_arm");
      }
      
      public function performMove() : Boolean
      {
         return false;
      }
      
      public function performAction() : Boolean
      {
         return false;
      }
      
      public function cleanup() : void
      {
         battleFsm = null;
         caster = null;
         enemies = null;
         atkStr = null;
         atkArm = null;
      }
      
      protected function buildEnemyArray() : void
      {
         enemies.splice(0,enemies.length);
         for each(var _loc1_ in battleFsm.board.entities)
         {
            // [Inference] BSF-Client #12: skip scenery props (e.g. "prop+pole03"). They are alive
            // board entities with a team but no combat stats, so the AI's plan math throws
            // "ArgumentError: No such stat: ARMOR" (BattleCalculationHelper.calculatePunctureBonus
            // -> stats.getStat(ARMOR)). Every real combatant has ARMOR; props don't -- use it to
            // keep props out of both enemies and friends. See A-0.log-ai test (prop+pole03).
            if(_loc1_.alive && _loc1_.stats.hasStat(StatType.ARMOR))
            {
               if(_loc1_.team != caster.team)
               {
                  enemies.push(_loc1_);
               }
               else
               {
                  friends.push(_loc1_);
               }
            }
         }
      }
      
      private function constructRestPlan() : AiPlan
      {
         var _loc1_:BattleAbilityDef = ss.battleFsm.board.abilityManager.factory.fetch("abl_rest") as BattleAbilityDef;
         return new AiPlan(this,null,_loc1_,null);
      }
      
      public function findPlans(param1:BattleAbilityDef, param2:StatType, param3:Vector.<BattleEntity>, param4:Vector.<AiPlan>, param5:int) : int
      {
         var _loc9_:BattleEntity = null;
         var _loc19_:AiPlan = null;
         var _loc18_:Array = null;
         var _loc21_:BattleMove = null;
         var _loc17_:int = 0;
         var _loc12_:int = 0;
         var _loc15_:int = 0;
         var _loc11_:int = 0;
         var _loc20_:int = 0;
         var _loc7_:BattleAbilityDef = null;
         var _loc22_:int = caster.stats.getValue(StatType.EXERTION);
         var _loc10_:int = caster.stats.getValue(StatType.WILLPOWER);
         var _loc6_:int = Math.min(_loc22_,_loc10_);
         var _loc13_:int = caster.stats.getStat(StatType.WILLPOWER).original;
         var _loc8_:int = int(caster.def.stats.getValue(StatType.MOVEMENT));
         var _loc14_:int = int(caster.def.stats.getValue(StatType.RANK));
         var _loc16_:int = param5;
         for(; _loc16_ < param3.length; _loc16_++)
         {
            if(_loc16_ > param5)
            {
               return _loc16_;
            }
            _loc9_ = param3[_loc16_];
            _loc19_ = null;
            _loc18_ = [false];
            _loc21_ = BattleMove.computeMoveToRange(param1,caster,_loc9_,ss.logger,_loc6_,_loc18_);
            if(_loc21_)
            {
               if(!_loc18_[0])
               {
                  _loc17_ = AiPlan.computePositionalWeight(this,this.caster.tile,null);
                  _loc12_ = AiPlan.computePositionalWeight(this,_loc21_.last,null);
                  if(_loc12_ <= _loc17_)
                  {
                     if(_loc10_ < _loc13_ && _loc10_ < _loc22_)
                     {
                        _loc19_ = constructRestPlan();
                        param4.push(_loc19_);
                        continue;
                     }
                  }
                  _loc19_ = new AiPlan(this,_loc21_,null,_loc9_);
                  param4.push(_loc19_);
                  continue;
               }
               _loc15_ = Math.max(0,_loc21_.numSteps - 1 - _loc8_);
               _loc6_ -= _loc15_;
            }
            if(_loc18_[0])
            {
               if(param1.tag == BattleAbilityTag.SPECIAL)
               {
                  _loc11_ = Math.min(_loc6_,_loc14_);
               }
               else
               {
                  _loc11_ = Math.min(_loc6_ + 1,param1.maxLevel);
               }
               _loc20_ = 1;
               while(_loc20_ <= _loc11_)
               {
                  _loc7_ = param1.getBattleAbilityDefLevel(_loc20_);
                  _loc19_ = new AiPlan(this,_loc21_,_loc7_,_loc9_);
                  param4.push(_loc19_);
                  _loc20_++;
               }
            }
         }
         return _loc16_;
      }
      
      protected function isInRangeOfEnemyForAttack() : Boolean
      {
         return false;
      }
      
      protected function getMovementTargetTiles() : Array
      {
         var _loc2_:* = null;
         var _loc5_:int = 0;
         var _loc4_:int = 0;
         var _loc1_:Array = [];
         for each(var _loc3_ in enemies)
         {
            _loc5_ = _loc3_.pos.x;
            _loc4_ = _loc3_.pos.y;
            if(_loc3_.rect.width == 1)
            {
               addMovementTargetTile(_loc5_,_loc4_ - 1,_loc1_);
               addMovementTargetTile(_loc5_ + 1,_loc4_,_loc1_);
               addMovementTargetTile(_loc5_,_loc4_ + 1,_loc1_);
               addMovementTargetTile(_loc5_ - 1,_loc4_,_loc1_);
            }
            else if(_loc3_.rect.width == 2)
            {
               addMovementTargetTile(_loc5_,_loc4_ + 2,_loc1_);
               addMovementTargetTile(_loc5_ + 1,_loc4_ + 2,_loc1_);
               addMovementTargetTile(_loc5_ + 2,_loc4_ + 1,_loc1_);
               addMovementTargetTile(_loc5_ + 2,_loc4_,_loc1_);
               addMovementTargetTile(_loc5_,_loc4_ - 1,_loc1_);
               addMovementTargetTile(_loc5_ + 1,_loc4_ - 1,_loc1_);
               addMovementTargetTile(_loc5_ - 1,_loc4_ + 1,_loc1_);
               addMovementTargetTile(_loc5_ - 1,_loc4_,_loc1_);
            }
         }
         return _loc1_;
      }
      
      protected function addMovementTargetTile(param1:int, param2:int, param3:Array) : void
      {
         var _loc4_:Tile = battleFsm.board.tiles.getTile(param1,param2);
         if(_loc4_ != null && param3.indexOf(_loc4_) == -1)
         {
            if(battleFsm.board.tiles.isTileBlockedForEntity(caster,_loc4_) == false)
            {
               param3.push(_loc4_);
            }
         }
      }
      
      protected function getNearestTile(param1:Array) : Tile
      {
         var _loc4_:int = 0;
         var _loc5_:int = 0;
         var _loc6_:int = 0;
         var _loc2_:Tile = null;
         var _loc3_:int = 2147483647;
         for each(var _loc7_ in param1)
         {
            _loc4_ = _loc7_.x - caster.x;
            _loc5_ = _loc7_.y - caster.y;
            _loc6_ = _loc4_ * _loc4_ + _loc5_ * _loc5_;
            if(_loc6_ < _loc3_)
            {
               _loc3_ = _loc6_;
               _loc2_ = _loc7_;
            }
         }
         return _loc2_;
      }
   }
}

