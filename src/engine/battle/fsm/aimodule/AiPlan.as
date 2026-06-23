package engine.battle.fsm.aimodule
{
   import engine.ability.def.AbilityDefLevel;
   import engine.battle.ability.BattleCalculationHelper;
   import engine.battle.ability.def.BattleAbilityDef;
   import engine.battle.ability.def.BattleAbilityDefLevels;
   import engine.battle.ability.def.BattleAbilityTag;
   import engine.battle.ability.model.BattleAbility;
   import engine.battle.ability.model.BattleAbilityValidation;
   import engine.battle.ability.model.StatChangeData;
   import engine.battle.board.model.IBattleEntity;
   import engine.battle.entity.model.BattleEntity;
   import engine.battle.fsm.BattleMove;
   import engine.core.util.StringUtil;
   import engine.stat.def.StatType;
   import engine.stat.model.Stat;
   import engine.tile.Tile;
   import engine.tile.def.TileLocation;
   import engine.tile.def.TileRect;
   import engine.tile.def.TileRectRange;
   import flash.errors.IllegalOperationError;
   
   public class AiPlan
   {
      
      public static var lastPlanId:int = 0;
      
      private static const WEIGHT_KILL:int = 200;
      
      private static const WEIGHT_STAR:int = 10;
      
      private static const WEIGHT_SELF_THREAT:Number = 0.5;
      
      private static const WEIGHT_ENEMY_THREAT:Number = 0.25;
      
      private static const WEIGHT_ABL_DAMAGE_STR:int = 45;
      
      private static const WEIGHT_ABL_DAMAGE_ARM:int = 20;
      
      private static const WEIGHT_ABL_MISSCHANCE:int = 2;
      
      private static const WEIGHT_FRIEND_DISTANCE:int = 15;
      
      private static const WEIGHT_MOVE:int = 2;
      
      public var ai:AiModuleBase;
      
      public var mv:BattleMove;
      
      public var abldef:BattleAbilityDef;
      
      public var target:BattleEntity;
      
      public var statchange_str:StatChangeData;
      
      public var statchange_arm:StatChangeData;
      
      public var killed:Boolean;
      
      public var weight:int;
      
      public var planId:int;
      
      private var killweight:int = 0;
      
      private var starsweight:int = 0;
      
      private var sweight_str:int = 0;
      
      private var sweight_arm:int = 0;
      
      private var pweight_enemy:int = 0;
      
      private var pweight_friend:int = 0;
      
      private var mvweight:int = 0;
      
      public function AiPlan(param1:AiModuleBase, param2:BattleMove, param3:BattleAbilityDef, param4:BattleEntity)
      {
         super();
         this.planId = ++lastPlanId;
         this.ai = param1;
         this.mv = param2;
         this.abldef = param3;
         this.target = param4;
         if(param3)
         {
            if(!BattleAbilityValidation.validateCosts(param3,param1.caster,param2,param1.ss.logger))
            {
               throw new IllegalOperationError("should have already been checked");
            }
            if(param3.root != param1.atkArm)
            {
               statchange_str = new StatChangeData();
               if(!BattleAbility.getStatChange(param3,param1.caster,StatType.STRENGTH,statchange_str,param4,param2))
               {
                  statchange_str = null;
               }
            }
            if(param3.root != param1.atkStr)
            {
               statchange_arm = new StatChangeData();
               if(!BattleAbility.getStatChange(param3,param1.caster,StatType.ARMOR,statchange_arm,param4,param2))
               {
                  statchange_arm = null;
               }
            }
            if(param4 && statchange_str)
            {
               if(statchange_str.amount > param4.stats.getValue(StatType.STRENGTH))
               {
                  killed = true;
               }
            }
         }
         computeWeight();
      }
      
      public static function computeStarsWeight(param1:AiModuleBase, param2:BattleAbilityDef, param3:BattleMove) : int
      {
         var _loc6_:int = 0;
         var _loc4_:int = 0;
         var _loc5_:int = 0;
         var _loc7_:int = 0;
         if(param2)
         {
            _loc7_ += param2.costs.getValue(StatType.WILLPOWER);
         }
         if(param3)
         {
            _loc6_ = param1.caster.stats.getValue(StatType.MOVEMENT);
            _loc4_ = Math.max(0,param3.numSteps - _loc6_ - 1);
            _loc7_ += _loc4_;
         }
         return int(_loc5_ - _loc7_ * 10);
      }
      
      public static function computeStrengthDamageWeight(param1:AiModuleBase, param2:StatChangeData, param3:IBattleEntity) : int
      {
         var _loc7_:Stat = null;
         var _loc5_:int = 0;
         var _loc6_:int = 0;
         var _loc9_:int = 0;
         var _loc8_:int = 0;
         var _loc4_:int = 0;
         if(param2 && param3)
         {
            _loc4_ -= param2.missChance * 2;
            _loc7_ = param3.stats.getStat(StatType.STRENGTH);
            _loc5_ = _loc7_.value;
            _loc6_ = Math.min(param2.amount,_loc5_);
            _loc4_ += _loc6_ * 45;
            if(_loc5_ - _loc6_ <= param2.amount)
            {
               _loc4_ *= 2;
            }
            _loc9_ = int(param3.stats.getStat(StatType.STRENGTH).original);
            _loc8_ = _loc9_ - _loc5_;
            _loc4_ += _loc8_ * 45 / 2;
         }
         return _loc4_;
      }
      
      public static function computeArmorDamageWeight(param1:AiModuleBase, param2:StatChangeData, param3:IBattleEntity) : int
      {
         var _loc4_:int = 0;
         var _loc7_:int = 0;
         var _loc6_:int = 0;
         var _loc5_:int = 0;
         if(param2 && param3)
         {
            _loc5_ += param2.amount * 20;
            _loc4_ = int(param3.stats.getStat(StatType.ARMOR).original);
            _loc7_ = int(param3.stats.getValue(StatType.ARMOR));
            _loc6_ = _loc4_ - _loc7_;
            _loc5_ += _loc6_ * 20 / 2;
         }
         return _loc5_;
      }
      
      public static function computePositionalWeightEnemies(param1:AiModuleBase, param2:Tile, param3:BattleEntity) : int
      {
         var _loc5_:* = null;
         var _loc4_:int = 0;
         for each(_loc5_ in param1.enemies)
         {
            if(_loc5_ != param3)
            {
               _loc4_ += computePositionalEnemyWeight(param1,param2.location,_loc5_);
            }
         }
         return _loc4_;
      }
      
      public static function computePositionalWeightFriends(param1:AiModuleBase, param2:Tile, param3:BattleEntity) : int
      {
         var _loc5_:* = null;
         var _loc4_:int = 0;
         var _loc6_:TileRect = new TileRect(param2.location,param1.caster.width,param1.caster.length);
         for each(_loc5_ in param1.friends)
         {
            _loc4_ += computePositionalFriendWeight(param1,_loc6_,_loc5_);
         }
         return _loc4_;
      }
      
      public static function computePositionalWeight(param1:AiModuleBase, param2:Tile, param3:BattleEntity) : int
      {
         var _loc4_:int = computePositionalWeightEnemies(param1,param2,param3);
         var _loc5_:int = computePositionalWeightEnemies(param1,param2,param3);
         return _loc4_ + _loc5_;
      }
      
      private static function computePositionalFriendWeight(param1:AiModuleBase, param2:TileRect, param3:BattleEntity) : int
      {
         var _loc5_:int = 0;
         var _loc4_:int = TileRectRange.computeRange(param2,param3.rect);
         _loc5_ = -_loc4_ * 15;
         if(param1.isRanged)
         {
            _loc5_ *= 2;
         }
         return _loc5_;
      }
      
      private static function computePositionalEnemyWeight(param1:AiModuleBase, param2:TileLocation, param3:BattleEntity) : int
      {
         var _loc7_:int = 0;
         var _loc4_:int = 0;
         var _loc11_:BattleAbilityDef = null;
         var _loc6_:int = 0;
         var _loc9_:int = 0;
         var _loc12_:int = 0;
         var _loc10_:BattleAbilityDefLevels = param3.def.attacks as BattleAbilityDefLevels;
         // [Inference] BSF-Client #12: getFirstAbilityByTag(ATTACK_STR) returns null for an enemy
         // unit with no strength attack (e.g. a Shieldbanger, whose basic attack is armor-only).
         // The decompiled code derefs .def here unconditionally, then guards _loc13_ below -- so a
         // strength-less enemy crashes the AI (#1009) before that guard ever runs. Compute _loc13_
         // null-safely; the existing "if(_loc13_)" check then simply skips that enemy's counter-
         // threat term. The dormant single-player AI never hit this because its scripted matchups
         // always had a strength attack on both sides. See "A-0.log-ai test2.txt".
         var _loc14_:AbilityDefLevel = _loc10_ ? _loc10_.getFirstAbilityByTag(BattleAbilityTag.ATTACK_STR) : null;
         var _loc13_:BattleAbilityDef = _loc14_ ? _loc14_.def as BattleAbilityDef : null;
         var _loc8_:TileRect = new TileRect(param2,param1.caster.rect.width,param1.caster.rect.length);
         var _loc5_:int = TileRectRange.computeRange(_loc8_,param3.rect);
         if(_loc13_)
         {
            if(_loc5_ < _loc13_.rangeMax && _loc5_ > _loc13_.rangeMin)
            {
               _loc7_ = BattleCalculationHelper.strengthNormalDamage(param3,param1.caster,0);
               _loc7_ = _loc7_ + BattleCalculationHelper.calculatePunctureBonus(param3,param1.caster);
               _loc4_ = param3.stats.getValue(StatType.ARMOR_BREAK);
               _loc7_ = Math.min(_loc7_,param1.caster.stats.getValue(StatType.STRENGTH));
               _loc4_ = Math.min(_loc4_,param1.caster.stats.getValue(StatType.ARMOR));
               if(_loc7_ > param1.caster.stats.getValue(StatType.STRENGTH))
               {
                  _loc7_ *= 2;
               }
               _loc7_ *= 45;
               _loc4_ *= 20;
               _loc12_ -= Math.max(_loc7_,_loc4_) * 0.5;
            }
         }
         if(param1.atkStr)
         {
            _loc11_ = param1.atkStr.def as BattleAbilityDef;
            if(_loc5_ < _loc11_.rangeMax && _loc5_ > _loc11_.rangeMin)
            {
               _loc6_ = BattleCalculationHelper.strengthNormalDamage(param1.caster,param3,0);
               _loc6_ = _loc6_ + BattleCalculationHelper.calculatePunctureBonus(param1.caster,param3);
               _loc9_ = param1.caster.stats.getValue(StatType.ARMOR_BREAK);
               _loc6_ = Math.min(_loc6_,param3.stats.getValue(StatType.STRENGTH));
               _loc9_ = Math.min(_loc9_,param3.stats.getValue(StatType.ARMOR));
               if(_loc6_ > param3.stats.getValue(StatType.STRENGTH))
               {
                  _loc6_ *= 2;
               }
               _loc6_ *= 45;
               _loc9_ *= 20;
               _loc12_ += Math.max(_loc6_,_loc9_) * 0.25;
            }
         }
         return _loc12_;
      }
      
      public static function compare(param1:AiPlan, param2:AiPlan) : int
      {
         return param2.weight - param1.weight;
      }
      
      public function toString() : String
      {
         var _loc1_:String = abldef ? abldef.id + "/" + abldef.level : "null";
         return StringUtil.padRight(planId.toString()," ",4) + " 𐄷=" + StringUtil.padRight(StringUtil.numberWithSign(weight)," ",5) + " " + StringUtil.padRight(ai.caster.id," ",24) + " mv=" + StringUtil.padRight(mv ? (mv.numSteps - 1).toString() : "0"," ",2) + " abl=" + StringUtil.padRight(_loc1_," ",18) + " trg=" + StringUtil.padRight(target ? target.id : "null"," ",15) + " ☠💀=" + StringUtil.padRight(StringUtil.numberWithSign(killweight)," ",4) + " str=" + StringUtil.padRight(statchange_str ? statchange_str.toString() : "null"," ",6) + " arm=" + StringUtil.padRight(statchange_arm ? statchange_arm.toString() : "null"," ",6) + " ⌖e=" + StringUtil.padRight(StringUtil.numberWithSign(pweight_enemy)," ",4) + " ⌖f=" + StringUtil.padRight(StringUtil.numberWithSign(pweight_friend)," ",4) + " sws=" + StringUtil.padRight(StringUtil.numberWithSign(sweight_str)," ",5) + " swa=" + StringUtil.padRight(StringUtil.numberWithSign(sweight_arm)," ",5) + " mw=" + StringUtil.padRight(StringUtil.numberWithSign(mvweight)
         ," ",5) + " ✶=" + starsweight;
      }
      
      private function computeWeight() : void
      {
         var _loc2_:int = 0;
         weight = 0;
         if(killed)
         {
            killweight = 200;
            if(target)
            {
               _loc2_ = 0;
               _loc2_ += target.stats.getValue(StatType.WILLPOWER) / 3;
               _loc2_ += target.stats.getValue(StatType.STRENGTH);
               _loc2_ += target.stats.getValue(StatType.ARMOR_BREAK);
               _loc2_ += target.stats.getValue(StatType.ARMOR) / 2;
               killweight += _loc2_;
            }
            weight += killweight;
         }
         sweight_str = computeStrengthDamageWeight(ai,statchange_str,target);
         weight += sweight_str;
         sweight_arm = computeArmorDamageWeight(ai,statchange_arm,target);
         weight += sweight_arm;
         starsweight = computeStarsWeight(ai,abldef,mv);
         weight += starsweight;
         if(mv)
         {
            mvweight = -(2 * mv.numSteps - 1);
            weight += mvweight;
         }
         var _loc3_:Tile = mv ? mv.last : ai.caster.tile;
         var _loc1_:BattleEntity = killed ? target : null;
         pweight_enemy = computePositionalWeightEnemies(ai,_loc3_,_loc1_);
         pweight_friend = computePositionalWeightFriends(ai,_loc3_,_loc1_);
         weight += pweight_enemy + pweight_friend;
         ai.ss.logger.debug("♕♔♘♞♛♜ computeWeight " + this);
      }
   }
}

