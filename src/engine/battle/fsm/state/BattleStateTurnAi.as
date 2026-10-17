package engine.battle.fsm.state
{
   import com.greensock.TweenMax;
   import engine.battle.fsm.BattleFsm;
   import engine.battle.fsm.BattleMoveEvent;
   import engine.battle.fsm.aimodule.AiModuleBase;
   import engine.battle.fsm.aimodule.AiModuleDredge;
   import engine.core.fsm.StateData;
   import engine.core.fsm.StatePhase;
   import engine.core.logging.ILogger;
   import engine.mod.ModGameSpeed;

   public class BattleStateTurnAi extends BattleStateTurnLocalBase
   {
      
      protected var aiModule:AiModuleBase = null;
      
      public function BattleStateTurnAi(param1:StateData, param2:BattleFsm, param3:ILogger)
      {
         super(param1,param2,param3,true);
         aiModule = new AiModuleDredge(this);
      }
      
      override protected function handleEnteredState() : void
      {
         super.handleEnteredState();
         battleFsm.turn.move.addEventListener("BattleMoveEvent.EXECUTED",moveExecutedHandler);
         battleFsm.turn.move.addEventListener("BattleMoveEvent.INTERRUPTED",moveInterruptedHandler);
         // [Inference] BSF-Client #31: the half-second pause before the computer moves (and
         // the one before it acts, below) runs on a real-time timer that the game clock's
         // fast-forward does not reach, so it is shortened by the same factor here.
         // ModGameSpeed.scale is 1 in normal play, which leaves both pauses at 0.5 s.
         TweenMax.delayedCall(0.5 / ModGameSpeed.scale,aiModule.performMove);
      }
      
      override protected function handleCleanup() : void
      {
         super.handleCleanup();
         TweenMax.killDelayedCallsTo(aiModule.performMove);
         TweenMax.killDelayedCallsTo(aiModule.performAction);
         aiModule.cleanup();
      }
      
      private function moveExecutedHandler(param1:BattleMoveEvent) : void
      {
         logger.debug("BattleStateTurnAI.moveExecutedHandler");
         TweenMax.delayedCall(0.5 / ModGameSpeed.scale,aiModule.performAction);
      }
      
      private function moveInterruptedHandler(param1:BattleMoveEvent) : void
      {
         logger.debug("BattleStateTurnLocal.moveInterruptedHandler");
         phase = StatePhase.COMPLETED;
      }
   }
}

