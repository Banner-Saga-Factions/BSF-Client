package engine.battle.fsm.state
{
   import engine.battle.board.model.BattlePartyType;
   import engine.battle.board.model.IBattleEntity;
   import engine.battle.fsm.BattleFsm;
   import engine.battle.fsm.BattleFsmConfig;
   import engine.battle.fsm.BattleTurn;
   import engine.battle.fsm.BattleTurnParty;
   import engine.battle.fsm.BattleTurnTeam;
   import engine.battle.fsm.txn.BattleTxnTurnInitSend;
   import engine.core.fsm.StateData;
   import engine.core.fsm.StatePhase;
   import engine.core.logging.ILogger;
   import engine.math.Hash;
   import engine.mod.ModAiSides;
   import engine.stat.def.StatType;
   import engine.stat.model.Stat;
   import flash.errors.IllegalOperationError;
   
   public class BattleStateNextTurn extends BaseBattleState
   {
      
      public static const SYNC_STATS:Array = [StatType.STRENGTH,StatType.ARMOR,StatType.WILLPOWER,StatType.ARMOR_BREAK,StatType.STRENGTH_ATTACK,StatType.MIN_STRENGTH_ATTACK,StatType.PUNCTURE_ATTACK_BONUS,StatType.MALICE_ATTACK_BONUS,StatType.BRINGTHEPAIN_COUNTER_BONUS,StatType.EXERTION,StatType.RESIST_STRENGTH,StatType.RESIST_ARMOR];
      
      private var txnSend:BattleTxnTurnInitSend;
      
      private var turnNumber:int;
      
      private var hash:int;
      
      private var hashStr:String;
      
      public function BattleStateNextTurn(param1:StateData, param2:BattleFsm, param3:ILogger, param4:int = 0)
      {
         super(param1,param2,param3,param4,700);
         turnNumber = battleFsm.turn ? battleFsm.turn.number + 1 : 0;
      }
      
      private function initSendHandler(param1:BattleTxnTurnInitSend) : void
      {
         if(param1.success)
         {
            nextTurn();
         }
      }
      
      private function nextTurn() : void
      {
         var _loc2_:IBattleEntity = battleFsm.order.aliveOrder[0];
         logger.debug("BattleStateNextTurn.nextTurn turn=" + turnNumber + " current=" + _loc2_);
         battleFsm.turn = new BattleTurn(_loc2_,turnNumber,hash,logger);
         var _loc1_:BattlePartyType = _loc2_.party.type;
         switch(_loc1_)
         {
            case BattlePartyType.LOCAL:
               // [Inference] BSF-Client #31, Wave 4a: AI vs AI. When the ModAiSides switch
               // says so, the computer plays the player's units too, with the same brain
               // state it uses for its own (BattleStateTurnAi reads which side's brain).
               // Offline only: an online battle's player's side belongs to a person, so
               // there the switch is ignored and the turn goes to the mouse as normal.
               if(ModAiSides.playerSide && !battleFsm.isOnline)
               {
                  logger.info("BSF #31 AI vs AI: the computer plays " + _loc2_.id + " on the player's side, turn " + turnNumber);
                  fsm.transitionTo(BattleStateTurnAi,data);
               }
               else
               {
                  fsm.transitionTo(BattleStateTurnLocal,data);
               }
               break;
            case BattlePartyType.REMOTE:
               fsm.transitionTo(BattleStateTurnRemote,data);
               break;
            case BattlePartyType.AI:
               if(BattleFsmConfig.enableAi)
               {
                  fsm.transitionTo(BattleStateTurnAi,data);
               }
               else
               {
                  fsm.transitionTo(BattleStateTurnLocal,data);
               }
               break;
            default:
               throw new IllegalOperationError("not handled party type " + _loc1_);
         }
      }
      
      private function computeHashStr() : void
      {
         var _loc7_:int = 0;
         var _loc5_:* = null;
         var _loc8_:* = null;
         var _loc9_:int = 0;
         var _loc2_:String = null;
         var _loc6_:Stat = null;
         var _loc11_:String = null;
         var _loc4_:IBattleEntity = battleFsm.turn ? battleFsm.turn.entity : null;
         hashStr = "ending_turn=" + (turnNumber - 1) + " ending_entity=" + _loc4_ + " executedAbilityId=" + battleFsm.board.abilityManager.nextExecutedId + "\n";
         var _loc12_:int = 0;
         var _loc3_:IBattleEntity = null;
         var _loc10_:Vector.<IBattleEntity> = battleFsm.order.getAliveParticipants(null);
         for each(_loc3_ in _loc10_)
         {
            _loc12_ = Math.max(_loc12_,_loc3_.id.length);
         }
         var _loc1_:String = "                         ";
         for each(_loc3_ in _loc10_)
         {
            hashStr += "sync=" + battleFsm.battleId + " " + _loc3_.id;
            _loc9_ = _loc12_ - _loc3_.id.length;
            if(_loc9_ > 0)
            {
               hashStr += _loc1_.substr(0,_loc9_);
            }
            _loc2_ = _loc3_.tile.toString();
            hashStr += " tile=" + _loc2_;
            _loc9_ = 8 - _loc2_.length;
            if(_loc9_ > 0)
            {
               hashStr += _loc1_.substr(0,_loc9_);
            }
            for each(var _loc13_ in SYNC_STATS)
            {
               _loc6_ = _loc3_.stats.getStat(_loc13_,false);
               if(_loc6_)
               {
                  _loc11_ = _loc6_.value.toString();
                  hashStr += "  " + _loc6_.type.abbrev + "=" + _loc11_;
                  _loc9_ = 3 - _loc11_.length;
                  if(_loc9_ > 0)
                  {
                     hashStr += _loc1_.substr(0,_loc9_);
                  }
               }
            }
            hashStr += "\n";
         }
      }
      
      private function computeHash() : int
      {
         computeHashStr();
         hash = Hash.DJBHash(hashStr);
         logger.debug("Turn Hash: " + hash + "\n" + hashStr);
         return hash;
      }
      
      override protected function handleEnteredState() : void
      {
         var _loc3_:Boolean = false;
         super.handleEnteredState();
         battleFsm.order.pruneDeadEntities();
         for each(var _loc4_ in battleFsm.order.turnTeams)
         {
            _loc3_ = true;
            for each(var _loc1_ in _loc4_.turnParties)
            {
               if(_loc1_.party.numMembers == 1 || _loc1_.members.length > 1)
               {
                  _loc3_ = false;
                  break;
               }
            }
            if(_loc3_)
            {
               battleFsm.order.commencePillaging();
               break;
            }
         }
         var _loc2_:IBattleEntity = battleFsm.order.next();
         if(!_loc2_)
         {
            battleFsm.addErrorMsg("Ragnarok Error");
            phase = StatePhase.FAILED;
            return;
         }
         if(battleFsm.order.numTeams == 1)
         {
            battleFsm.addErrorMsg("Nidhogg Error");
            phase = StatePhase.FAILED;
            return;
         }
         if(battleFsm.isOnline)
         {
            computeHash();
            txnSend = new BattleTxnTurnInitSend(battleFsm.battleId,turnNumber,hashStr,hash,_loc2_,battleFsm.session.credentials,initSendHandler,battleFsm,logger);
            addTxn(txnSend);
            txnSend.send(battleFsm.session.communicator,null,0);
         }
         else
         {
            nextTurn();
         }
      }
   }
}

