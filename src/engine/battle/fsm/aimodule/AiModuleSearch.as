package engine.battle.fsm.aimodule
{
   import engine.ability.def.AbilityDefLevel;
   import engine.battle.ability.BattleCalculationHelper;
   import engine.battle.ability.def.BattleAbilityDef;
   import engine.battle.ability.def.BattleAbilityDefLevels;
   import engine.battle.ability.def.BattleAbilityTag;
   import engine.battle.ability.model.BattleAbility;
   import engine.battle.board.model.IBattleBoard;
   import engine.battle.board.model.IBattleEntity;
   import engine.battle.entity.model.BattleEntity;
   import engine.battle.fsm.BattleMove;
   import engine.battle.fsm.state.BattleStateTurnAi;
   import engine.stat.def.StatType;
   import engine.tile.Tile;
   import flash.utils.Dictionary;

   /**
    * AiModuleSearch — NEW FILE (not in original decompile). BSF-Client #31, Wave 4.
    *
    * The computer opponent with a one-move look-ahead. It thinks exactly as AiModuleDredge
    * does, then, before it commits, asks of its best few plans: "if I do this, what is the
    * worst the enemy who acts next can do back to me?" That threat, in the planner's own
    * points, is taken off each plan's score, and the best plan after that is played.
    *
    * [Inference] HOW THE REPLY IS WORKED OUT, AND WHY NOT BY PLAYING IT. The game's pretend
    * mode (BattleBoard.fake) is one on/off switch: switching it on gives every unit a
    * throw-away copy of its stats, switching it off throws every copy away, and switching it
    * to the value it already has does nothing. So pretend mode cannot be nested: playing the
    * reply in pretend mode (BattleAbility.getStatChange) would end the pretend mode our own
    * imagined move lives in. Instead our move is imagined once, and the reply is worked out
    * from the pretend stats with the game's own attack rule:
    *   - strength attack (Op_DamageStr, the rule all three basic strength attacks use):
    *     damage = attacker's strength + strength bonus + puncture bonus - target's armor.
    *     If that is 0 or less, the attack lands for 1 point, or misses for 0, with a miss
    *     chance of 10% per point short, at most 80%. The puncture bonus only counts when the
    *     attacker does not move first.
    *   - armor attack: BattleCalculationHelper.armorNormalDamage.
    * BattleCalculationHelper.strengthNormalMiss is not used: nothing in the game calls it,
    * and it counts one point more than the attack itself does.
    *
    * POINTS, similar to AiPlan.computeWeight's (without its doubled near-kill term, strength- or armor-lost
    * bonus or miss-chance term): 45 per point of strength taken,
    * 20 per point of armor, and a kill earns the same 200 + the victim's worth that a kill of
    * ours earns. A strength attack's points are scaled by its chance to land.
    *
    * WHO REPLIES. The next enemy in the turn order (BattleTurnOrder.aliveOrder) whose pretend
    * strength is above 0, so if our imagined move kills that unit, the enemy after it replies.
    * A pretend death leaves "alive" set; strength 0 or below is the test.
    *
    * WHAT IT CANNOT SEE. The reply's route is found on the real board, where the tile we
    * imagine leaving still shows us standing on it (our unit's move events are muted while
    * imagining, as getStatChange mutes them, so the board's map of who stands where is not
    * told). Distances use the imagined position. The reply's special abilities are not
    * scored, and neither is a willpower-boosted hit.
    *
    * NEVER STALLS A TURN. Any error is logged and the normal choice (the top plan) is played.
    */
   public class AiModuleSearch extends AiModuleDredge
   {

      /** How much of the reply's points come off a plan's score. 1 = all of them. */
      public static const WEIGHT_REPLY:Number = 1;

      /** How many of the best different plans get the look-ahead. */
      private static const MAX_PLANS:int = 6;

      // The same weights as AiPlan (its constants are private there).
      private static const WEIGHT_KILL:int = 200;

      private static const WEIGHT_ABL_DAMAGE_STR:int = 45;

      private static const WEIGHT_ABL_DAMAGE_ARM:int = 20;

      // The miss rule's settings, as all three basic strength attacks set them
      // (abl_melee_str, abl_spear_str, abl_bow_str: missChancePer 10, maxMissChance 80,
      // damageOnMiss 1; decoded from the game's ability files 2026-10-17).
      private static const MISS_CHANCE_PER_POINT:Number = 0.1;

      private static const MAX_MISS_CHANCE:Number = 0.8;

      private static const DAMAGE_WHEN_SHORT:int = 1;

      public function AiModuleSearch(param1:BattleStateTurnAi)
      {
         super(param1);
      }

      override protected function pickPlan(param1:Vector.<AiPlan>) : AiPlan
      {
         var _loc2_:AiPlan = param1[0];
         try
         {
            var _loc3_:Vector.<AiPlan> = distinctTopPlans(param1);
            var _loc4_:Number = -Infinity;
            for each(var _loc5_:AiPlan in _loc3_)
            {
               var _loc6_:Object = scoreReply(_loc5_);
               var _loc7_:Number = _loc5_.weight - WEIGHT_REPLY * _loc6_.points;
               ss.logger.debug("BSF #31 look-ahead: plan " + _loc5_.planId + " old " + _loc5_.weight + " reply " + Math.round(_loc6_.points) + " by " + _loc6_.by + " on " + _loc6_.on + " -> " + Math.round(_loc7_));
               // Strictly better only, so a tie keeps the plan the normal brain ranked higher.
               if(_loc7_ > _loc4_)
               {
                  _loc4_ = _loc7_;
                  _loc2_ = _loc5_;
               }
            }
            if(_loc2_ != param1[0])
            {
               ss.logger.info("BSF #31 look-ahead: " + caster.id + " changed its choice from plan " + param1[0].planId + " to plan " + _loc2_.planId + " after looking at " + _loc3_.length + " plans");
            }
            else
            {
               ss.logger.debug("BSF #31 look-ahead: " + caster.id + " kept plan " + _loc2_.planId + " after looking at " + _loc3_.length + " plans");
            }
         }
         catch(e:Error)
         {
            ss.logger.error("BSF #31 look-ahead failed, playing the top plan: " + (caster ? caster.id : "?") + ": " + e.getStackTrace());
            return param1[0];
         }
         return _loc2_;
      }

      /**
       * The best MAX_PLANS plans, keeping only the first of any that end on the same tile with
       * the same ability (and level) on the same target. findPlans makes the same rest plan
       * once per enemy, so without this the look-ahead could spend its six looks on one idea.
       */
      private function distinctTopPlans(param1:Vector.<AiPlan>) : Vector.<AiPlan>
      {
         var _loc2_:Vector.<AiPlan> = new Vector.<AiPlan>();
         var _loc3_:Dictionary = new Dictionary();
         for each(var _loc4_:AiPlan in param1)
         {
            if(_loc2_.length >= MAX_PLANS)
            {
               break;
            }
            var _loc5_:Tile = _loc4_.mv ? _loc4_.mv.last : null;
            var _loc6_:String = (_loc5_ ? _loc5_.x + "," + _loc5_.y : "here") + "|" + (_loc4_.abldef ? _loc4_.abldef.id + "/" + _loc4_.abldef.level : "none") + "|" + (_loc4_.target ? _loc4_.target.id : "none");
            if(_loc3_[_loc6_])
            {
               continue;
            }
            _loc3_[_loc6_] = true;
            _loc2_.push(_loc4_);
         }
         return _loc2_;
      }

      /**
       * Imagine our plan, then score the next enemy's best single reply. Returns
       * {points, by, on}. Everything set up here is undone in the finally block, in the order
       * BattleAbility.getStatChange undoes it: the unit can only be moved while pretend mode is
       * off (Entity.setPos does nothing for a unit holding pretend stats), so it is moved before
       * pretend mode starts and moved back after it ends.
       */
      private function scoreReply(param1:AiPlan) : Object
      {
         var _loc2_:Object = {
            "points":0,
            "by":"nobody",
            "on":"nobody"
         };
         var _loc3_:IBattleBoard = battleFsm.board;
         var _loc4_:Tile = caster.tile;
         try
         {
            caster.suppressMoveEvents = true;
            if(param1.mv)
            {
               caster.setPos(param1.mv.last.x,param1.mv.last.y);
            }
            _loc3_.fake = true;
            if(param1.abldef && param1.target)
            {
               var _loc5_:BattleAbility = new BattleAbility(caster,param1.abldef,_loc3_.abilityManager);
               _loc5_.targetSet.setTarget(param1.target);
               _loc5_.execute(null);
            }
            var _loc6_:BattleEntity = nextReplier();
            if(_loc6_)
            {
               _loc2_.by = _loc6_.id;
               scoreBestAttack(_loc6_,_loc2_);
            }
         }
         finally
         {
            _loc3_.fake = false;
            if(_loc4_)
            {
               caster.setPos(_loc4_.x,_loc4_.y);
            }
            caster.suppressMoveEvents = false;
         }
         return _loc2_;
      }

      /** The next enemy to act whose pretend strength is above 0, or null. */
      private function nextReplier() : BattleEntity
      {
         var _loc1_:Vector.<IBattleEntity> = battleFsm.order ? battleFsm.order.aliveOrder : null;
         if(!_loc1_)
         {
            return null;
         }
         for each(var _loc2_:IBattleEntity in _loc1_)
         {
            var _loc3_:BattleEntity = _loc2_ as BattleEntity;
            if(!_loc3_ || _loc3_.team == caster.team || !_loc3_.alive || !_loc3_.stats.hasStat(StatType.ARMOR))
            {
               continue;
            }
            if(_loc3_.stats.getValue(StatType.STRENGTH) > 0)
            {
               return _loc3_;
            }
         }
         return null;
      }

      /** The replier's best basic attack on any of our units it can reach this turn. */
      private function scoreBestAttack(param1:BattleEntity, param2:Object) : void
      {
         var _loc3_:BattleAbilityDefLevels = param1.def.attacks as BattleAbilityDefLevels;
         if(!_loc3_)
         {
            return;
         }
         var _loc4_:BattleAbilityDef = levelOne(_loc3_.getFirstAbilityByTag(BattleAbilityTag.ATTACK_STR));
         var _loc5_:BattleAbilityDef = levelOne(_loc3_.getFirstAbilityByTag(BattleAbilityTag.ATTACK_ARM));
         // The same extra-movement allowance findPlans gives our own units.
         var _loc6_:int = Math.min(param1.stats.getValue(StatType.EXERTION),param1.stats.getValue(StatType.WILLPOWER));
         var _loc7_:Vector.<BattleEntity> = friends.concat();
         _loc7_.push(caster);
         for each(var _loc8_:BattleEntity in _loc7_)
         {
            if(_loc8_.stats.getValue(StatType.STRENGTH) <= 0)
            {
               continue;
            }
            var _loc9_:Number = 0;
            var _loc10_:int = _loc4_ ? reach(_loc4_,param1,_loc8_,_loc6_) : 0;
            if(_loc10_ > 0)
            {
               _loc9_ = strengthPoints(param1,_loc8_,_loc10_ == 1);
            }
            if(_loc5_ && reach(_loc5_,param1,_loc8_,_loc6_) > 0)
            {
               _loc9_ = Math.max(_loc9_,BattleCalculationHelper.armorNormalDamage(param1,_loc8_,0) * WEIGHT_ABL_DAMAGE_ARM);
            }
            if(_loc9_ > param2.points)
            {
               param2.points = _loc9_;
               param2.on = _loc8_.id;
            }
         }
      }

      private static function levelOne(param1:AbilityDefLevel) : BattleAbilityDef
      {
         var _loc2_:BattleAbilityDef = param1 ? param1.def as BattleAbilityDef : null;
         return _loc2_ ? _loc2_.getAbilityDefForLevel(1) as BattleAbilityDef : null;
      }

      /**
       * Whether the attacker can bring the attack to bear on the target this turn, by the game's
       * own route-finding (BattleMove.computeMoveToRange, as findPlans uses it): 0 no, 1 from
       * where it stands, 2 after a move.
       */
      private function reach(param1:BattleAbilityDef, param2:BattleEntity, param3:BattleEntity, param4:int) : int
      {
         var _loc5_:Array = [false];
         var _loc6_:BattleMove = BattleMove.computeMoveToRange(param1,param2,param3,ss.logger,param4,_loc5_);
         var _loc7_:int = !_loc5_[0] ? 0 : (_loc6_ && _loc6_.numSteps > 1 ? 2 : 1);
         if(_loc6_)
         {
            _loc6_.cleanup();
         }
         return _loc7_;
      }

      /** Op_DamageStr's rule, read off the pretend stats, in AiPlan's points. */
      private function strengthPoints(param1:BattleEntity, param2:BattleEntity, param3:Boolean) : Number
      {
         var _loc4_:int = param1.stats.getValue(StatType.STRENGTH) + param1.stats.getValue(StatType.STRENGTH_ATTACK);
         if(param3)
         {
            _loc4_ += BattleCalculationHelper.calculatePunctureBonus(param1,param2);
         }
         var _loc5_:int = _loc4_ - param2.stats.getValue(StatType.ARMOR);
         var _loc6_:Number = 0;
         if(_loc5_ <= 0)
         {
            _loc6_ = Math.min(MAX_MISS_CHANCE,-_loc5_ * MISS_CHANCE_PER_POINT);
            _loc5_ = DAMAGE_WHEN_SHORT;
         }
         var _loc7_:int = param2.stats.getValue(StatType.STRENGTH);
         var _loc8_:Number = Math.min(_loc5_,_loc7_) * WEIGHT_ABL_DAMAGE_STR;
         if(_loc5_ >= _loc7_)
         {
            _loc8_ += killWorth(param2);
         }
         return (1 - _loc6_) * _loc8_;
      }

      /** What AiPlan.computeWeight adds for a kill, here for one of ours. */
      private static function killWorth(param1:BattleEntity) : Number
      {
         return WEIGHT_KILL + int(param1.stats.getValue(StatType.WILLPOWER) / 3) + param1.stats.getValue(StatType.STRENGTH) + param1.stats.getValue(StatType.ARMOR_BREAK) + int(param1.stats.getValue(StatType.ARMOR) / 2);
      }
   }
}
