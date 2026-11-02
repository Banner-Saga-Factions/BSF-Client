package engine.battle.fsm.aimodule
{
   import engine.battle.ability.def.BattleAbilityDef;
   import engine.battle.ability.model.BattleAbility;
   import engine.battle.ability.model.BattleAbilityManager;
   import engine.battle.fsm.BattleMove;
   import engine.battle.fsm.state.BattleStateTurnAi;
   import engine.battle.fsm.state.turn.cmd.BattleTurnCmdAction;
   import engine.math.Rng;
   import engine.mod.ModAiBrain;
   import engine.stat.def.StatType;
   import engine.tile.Tile;
   import flash.events.TimerEvent;
   import flash.utils.Dictionary;
   import flash.utils.Timer;
   
   public class AiModuleDredge extends AiModuleBase
   {
      
      // [Inference] BSF-Client #31: protected (was private) so the look-ahead brain,
      // AiModuleSearch, can read the scored plans. Only pickPlan below changes hands.
      protected var chosenPlan:AiPlan;

      protected var plans:Vector.<AiPlan> = new Vector.<AiPlan>();
      
      private var timer:Timer = new Timer(0,0);
      
      private var stars:int = 0;
      
      private var str1:BattleAbilityDef = null;
      
      private var brk1:BattleAbilityDef = null;
      
      private var brkIndex:int;
      
      private var strIndex:int;

      // [Inference] BSF-Client #31: which special the special passes have reached, and which
      // enemy within it (the same one-enemy-per-tick pattern as strIndex and brkIndex).
      private var specPass:int;

      private var specIndex:int;

      public function AiModuleDredge(param1:BattleStateTurnAi)
      {
         super(param1);
      }
      
      override public function performMove() : Boolean
      {
         var _loc1_:* = null;
         var _loc3_:* = null;
         if(battleFsm.turn.suspended || ss.skipped)
         {
            return false;
         }
         timer.addEventListener("timer",timerHandler);
         timer.start();
         var _loc4_:int = caster.stats.getValue(StatType.EXERTION);
         var _loc2_:int = caster.stats.getValue(StatType.WILLPOWER);
         stars = Math.min(_loc4_,_loc2_);
         str1 = atkStr ? atkStr.def.getAbilityDefForLevel(1) as BattleAbilityDef : null;
         brk1 = atkArm ? atkArm.def.getAbilityDefForLevel(1) as BattleAbilityDef : null;
         return true;
      }
      
      private function timerHandler(param1:TimerEvent) : void
      {
         tickAi();
      }
      
      override public function cleanup() : void
      {
         if(timer)
         {
            timer.removeEventListener("timer",timerHandler);
            timer.stop();
            timer = null;
         }
         super.cleanup();
      }
      
      private function tickAi() : void
      {
         if(str1)
         {
            if(strIndex < enemies.length)
            {
               strIndex = findPlans(str1,StatType.STRENGTH,enemies,plans,strIndex);
               return;
            }
         }
         if(brk1)
         {
            if(brkIndex < enemies.length)
            {
               brkIndex = findPlans(brk1,StatType.ARMOR,enemies,plans,brkIndex);
               return;
            }
         }
         // [Inference] BSF-Client #31: the original never tried the unit's special abilities.
         // After the strength and armor passes, try each single-enemy special (AiModuleBase
         // .specials) against each enemy, one enemy per tick.
         if(specials)
         {
            while(specPass < specials.length)
            {
               if(specIndex < enemies.length)
               {
                  specIndex = findSpecialPlans(specials[specPass],specIndex);
                  return;
               }
               specPass++;
               specIndex = 0;
            }
         }
         if(!chosenPlan)
         {
            chooseBestPlan();
         }
      }

      /**
       * [Inference] BSF-Client #31: one special pass against one enemy. findPlans also makes
       * "walk closer" and "rest" plans, which the strength or armor pass already made, so its
       * plans go to a scratch list and only those that use the special and take away some
       * strength or armor join the real list. So a special that does nothing at once (Malice) is
       * tried but never chosen, and resting still wins when nothing better is on offer.
       *
       * The log line also counts the battle's real dice rolled while imagining: the game counts
       * every roll (Rng.sampleCount), and imagining (pretend mode) is meant to roll its own
       * separate dice (BattleAbilityManager.rng), so this should stay 0.
       */
      private function findSpecialPlans(param1:BattleAbilityDef, param2:int) : int
      {
         var _loc3_:Vector.<AiPlan> = new Vector.<AiPlan>();
         var _loc4_:Rng = battleFsm.board.abilityManager.rng;
         var _loc5_:int = _loc4_ ? _loc4_.sampleCount : 0;
         var _loc6_:int = 0;
         var _loc7_:int;
         var _loc8_:String = param2 < enemies.length ? enemies[param2].id : "?";
         try
         {
            _loc7_ = findPlans(param1,StatType.STRENGTH,enemies,_loc3_,param2);
         }
         catch(e:Error)
         {
            // Skip this special for the rest of the turn rather than leave the turn stuck.
            ss.logger.error("BSF #31 special pass failed: " + caster.id + " " + param1.id + " vs " + _loc8_ + ": " + e.getStackTrace());
            specPass++;
            specIndex = 0;
            return 0;
         }
         for each(var _loc9_:AiPlan in _loc3_)
         {
            if(isUsefulSpecialPlan(_loc9_))
            {
               plans.push(_loc9_);
               _loc6_++;
            }
         }
         ss.logger.debug("BSF #31 special pass: " + caster.id + " " + param1.id + " vs " + _loc8_ + ": kept " + _loc6_ + " of " + _loc3_.length + " plans; real dice rolled while imagining: " + (_loc4_ ? _loc4_.sampleCount - _loc5_ : -1));
         return _loc7_;
      }

      private static function isUsefulSpecialPlan(param1:AiPlan) : Boolean
      {
         if(!param1 || !param1.abldef)
         {
            return false;
         }
         if(param1.statchange_str != null && param1.statchange_str.amount > 0)
         {
            return true;
         }
         return param1.statchange_arm != null && param1.statchange_arm.amount > 0;
      }
      
      private function chooseBestPlan() : void
      {
         var _loc1_:BattleMove = null;
         var _loc3_:int = 0;
         timer.removeEventListener("timer",timerHandler);
         timer.stop();
         plans.sort(AiPlan.compare);
         chosenPlan = plans.length > 0 ? pickPlan(plans) : null;
         if(!chosenPlan)
         {
            chosenPlan = makeNullPlan();
         }
         var _loc2_:BattleMove = battleFsm.turn.move;
         if(chosenPlan)
         {
            ss.logger.debug("♕♔♘♞♛♜ CHOSE PLAN [" + brainName + "] " + chosenPlan);
            _loc1_ = chosenPlan.mv;
            if(_loc1_)
            {
               _loc3_ = 1;
               while(_loc3_ < _loc1_.numSteps)
               {
                  _loc2_.addStep(_loc1_.getStep(_loc3_));
                  _loc3_++;
               }
            }
         }
         _loc2_.setCommitted("AiModuleDredge.performMove");
         battleFsm.turn.entity.mobility.executeMove(_loc2_);
      }
      
      /**
       * [Inference] BSF-Client #31: the one seam for the look-ahead brain. Given the plans
       * sorted best first (never empty), return the one to play. In normal play this brain
       * takes the top plan, as the original did; AiModuleSearch overrides it.
       */
      protected function pickPlan(param1:Vector.<AiPlan>) : AiPlan
      {
         // Wave 4a: in a measuring run (margin above 0), any different plan within the margin
         // of the best may be played instead. Margin 0, normal play, is the top plan as before.
         if(ModAiBrain.margin <= 0)
         {
            return param1[0];
         }
         var _loc2_:Vector.<AiPlan> = distinctTopPlans(param1,int.MAX_VALUE);
         var _loc3_:Vector.<Number> = new Vector.<Number>();
         for each(var _loc4_:AiPlan in _loc2_)
         {
            _loc3_.push(_loc4_.weight);
         }
         return pickNearBest(_loc2_,_loc3_,param1[0]);
      }

      /**
       * [Inference] BSF-Client #31, Wave 4a: the near-best pick, so that two fixed brains do
       * not keep replaying one battle. Given candidate plans, their scores (same order)
       * and the plan the brain would normally play, return one picked at random among those
       * scoring within ModAiBrain.margin of the best score. The random numbers are
       * ModAiBrain's own (seeded by the match runner), not the game's dice. With margin 0,
       * no seed sent, or only one plan near the top, it returns the normal plan.
       */
      protected function pickNearBest(param1:Vector.<AiPlan>, param2:Vector.<Number>, param3:AiPlan) : AiPlan
      {
         if(ModAiBrain.margin <= 0 || !ModAiBrain.seeded || param1.length < 2 || param1.length != param2.length)
         {
            return param3;
         }
         var _loc4_:Number = -Infinity;
         for each(var _loc5_:Number in param2)
         {
            _loc4_ = Math.max(_loc4_,_loc5_);
         }
         var _loc6_:Vector.<AiPlan> = new Vector.<AiPlan>();
         var _loc7_:int = 0;
         while(_loc7_ < param1.length)
         {
            if(param2[_loc7_] >= _loc4_ - ModAiBrain.margin)
            {
               _loc6_.push(param1[_loc7_]);
            }
            _loc7_++;
         }
         if(_loc6_.length < 2)
         {
            return param3;
         }
         var _loc8_:AiPlan = _loc6_[ModAiBrain.pickIndex(_loc6_.length)];
         if(_loc8_ != param3)
         {
            ss.logger.info("BSF #31 near-best: " + caster.id + " played plan " + _loc8_.planId + " instead of plan " + param3.planId + ", one of " + _loc6_.length + " within " + ModAiBrain.margin + " points of the best");
         }
         return _loc8_;
      }

      /**
       * [Inference] BSF-Client #31: the best (at most param2) plans, keeping only the first of any that end on the same tile with
       * the same ability (and level) on the same target. findPlans makes the same rest plan
       * once per enemy, so without this the look-ahead could spend its six looks on one idea, and
       * the near-best pick (Wave 4a) would mostly pick copies of one plan. Moved here from
       * AiModuleSearch in Wave 4a so both brains share it.
       */
      protected function distinctTopPlans(param1:Vector.<AiPlan>, param2:int) : Vector.<AiPlan>
      {
         var _loc2_:Vector.<AiPlan> = new Vector.<AiPlan>();
         var _loc3_:Dictionary = new Dictionary();
         for each(var _loc4_:AiPlan in param1)
         {
            if(_loc2_.length >= param2)
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
       * [Inference] BSF-Client #31, Wave 4a: this brain's name, written on each CHOSE PLAN log
       * line so the match runner can count each brain's choices when both sides are played by
       * the computer. AiModuleSearch overrides it.
       */
      protected function get brainName() : String
      {
         return ModAiBrain.DREDGE;
      }

      private function makeNullPlan() : AiPlan
      {
         return new AiPlan(this,null,null,null);
      }
      
      override public function performAction() : Boolean
      {
         if(!battleFsm || battleFsm.turn.suspended || ss.skipped)
         {
            return false;
         }
         var _loc1_:BattleAbilityManager = battleFsm.board.abilityManager;
         if(!chosenPlan.abldef)
         {
            if(battleFsm.turn.move.numSteps > 1)
            {
               chosenPlan.abldef = _loc1_.factory.fetch("abl_end") as BattleAbilityDef;
            }
            else
            {
               chosenPlan.abldef = _loc1_.factory.fetch("abl_rest") as BattleAbilityDef;
            }
            chosenPlan.target = null;
         }
         var _loc2_:BattleAbility = new BattleAbility(caster,chosenPlan.abldef,_loc1_);
         if(chosenPlan.target)
         {
            _loc2_.targetSet.setTarget(chosenPlan.target);
         }
         ss.cmdSeq.addCmd(new BattleTurnCmdAction(ss,0,true,_loc2_,true));
         return true;
      }
      
      protected function test01_move() : void
      {
         var _loc1_:Tile = null;
         var _loc4_:Tile = battleFsm.turn.entity.tile;
         var _loc3_:int = _loc4_.x;
         var _loc2_:int = _loc4_.y;
         _loc3_--;
         _loc1_ = battleFsm.board.tiles.getTile(_loc3_,_loc2_);
         battleFsm.turn.move.addStep(_loc1_);
         _loc2_--;
         _loc1_ = battleFsm.board.tiles.getTile(_loc3_,_loc2_);
         battleFsm.turn.move.addStep(_loc1_);
         _loc3_++;
         _loc1_ = battleFsm.board.tiles.getTile(_loc3_,_loc2_);
         battleFsm.turn.move.addStep(_loc1_);
         _loc2_++;
         _loc1_ = battleFsm.board.tiles.getTile(_loc3_,_loc2_);
         battleFsm.turn.move.addStep(_loc1_);
         battleFsm.turn.move.setCommitted("tes01_move");
         battleFsm.turn.entity.mobility.executeMove(battleFsm.turn.move);
      }
      
      protected function test02_move() : void
      {
         var _loc1_:Tile = null;
         var _loc4_:Tile = battleFsm.turn.entity.tile;
         var _loc3_:int = _loc4_.x;
         var _loc2_:int = _loc4_.y;
         _loc2_++;
         _loc1_ = battleFsm.board.tiles.getTile(_loc3_,_loc2_);
         battleFsm.turn.move.addStep(_loc1_);
         _loc2_++;
         _loc1_ = battleFsm.board.tiles.getTile(_loc3_,_loc2_);
         battleFsm.turn.move.addStep(_loc1_);
         _loc2_--;
         _loc1_ = battleFsm.board.tiles.getTile(_loc3_,_loc2_);
         battleFsm.turn.move.addStep(_loc1_);
         _loc2_--;
         _loc1_ = battleFsm.board.tiles.getTile(_loc3_,_loc2_);
         battleFsm.turn.move.addStep(_loc1_);
         battleFsm.turn.move.setCommitted("test02_move");
         battleFsm.turn.entity.mobility.executeMove(battleFsm.turn.move);
      }
   }
}

