package engine.battle.fsm
{
   import engine.battle.ability.def.BattleAbilityDef;
   import engine.battle.board.model.IBattleEntity;
   import engine.battle.board.model.IBattleMove;
   import engine.battle.sim.TileDiamond;
   import engine.battle.sim.TileRectHugger;
   import engine.core.logging.ILogger;
   import engine.path.IPath;
   import engine.path.IPathGraphLink;
   import engine.path.IPathGraphNode;
   import engine.path.Path;
   import engine.path.PathEvent;
   import engine.path.PathFloodSolver;
   import engine.path.PathFloodSolverNode;
   import engine.path.PathStatus;
   import engine.stat.def.StatType;
   import engine.stat.model.StatEvent;
   import engine.tile.Tile;
   import engine.tile.def.TileLocation;
   import engine.tile.def.TileRect;
   import engine.tile.def.TileRectRange;
   import flash.errors.IllegalOperationError;
   import flash.events.EventDispatcher;
   
   public class BattleMove extends EventDispatcher implements IBattleMove
   {
      
      private var _entity:IBattleEntity;
      
      public var wayPointTile:Tile;
      
      public var wayPointSteps:int = 1;
      
      protected var steps:Vector.<Tile> = new Vector.<Tile>();
      
      private var _path:IPath;
      
      public var flood:PathFloodSolver;
      
      private var _executed:Boolean;
      
      private var _executing:Boolean;
      
      private var _committed:Boolean;
      
      private var _interrupted:Boolean;
      
      private var _forcedMove:Boolean = false;
      
      private var _reactToEntityIntersect:Boolean = false;
      
      private var _maxStars:int = 1000;
      
      private var _searchBonus:int = 0;
      
      public function BattleMove(param1:IBattleEntity, param2:int = 1000, param3:int = 0)
      {
         super();
         if(!param1)
         {
            throw new ArgumentError("BattleMove null entity");
         }
         this._entity = param1;
         steps.push(param1.tile);
         _maxStars = param2;
         _searchBonus = param3;
         updateFloods();
      }
      
      private static function heuristicFloodDistance(param1:Tile, param2:Tile) : Number
      {
         var _loc3_:int = Math.abs(param1.x - param2.x);
         var _loc4_:int = Math.abs(param1.y - param2.y);
         return _loc3_ * 100 + _loc4_;
      }
      
      public static function computeMoveToRange(param1:BattleAbilityDef, param2:IBattleEntity, param3:IBattleEntity, param4:ILogger, param5:int, param6:Array) : BattleMove
      {
         var _loc7_:int = TileRectRange.computeRange(param3.rect,param2.rect);
         var _loc10_:BattleMove = new BattleMove(param2,param5);
         var _loc9_:int = int(param2.stats.getValue(StatType.MOVEMENT));
         param6[0] = true;
         if(param1.rangeMax < 0)
         {
            param4.info("Infinite-range no move");
            return _loc10_;
         }
         if(param1.rangeMax > 0 && _loc7_ > param1.rangeMax)
         {
            param4.debug("Op_MoveToRange execute too far");
            if(_loc10_.pathToDiamond(param3.rect,param1.rangeMin,param1.rangeMax,true,_loc9_ + param5))
            {
               return _loc10_;
            }
         }
         else
         {
            if(!(param1.rangeMin > 0 && _loc7_ < param1.rangeMin))
            {
               param4.debug("Op_MoveToRange execute range perfect " + _loc7_);
               return null;
            }
            param4.debug("Op_MoveToRange execute too close");
            if(_loc10_.pathToDiamond(param3.rect,param1.rangeMin,param1.rangeMax,true,_loc9_ + param5))
            {
               return _loc10_;
            }
         }
         param4.debug("Op_MoveToRange execute just get close");
         param6[0] = false;
         var _loc8_:TileRect = param3.rect;
         if(_loc10_.pathToDiamond(_loc8_,param1.rangeMin,param1.rangeMax,true,_loc9_ + param5))
         {
         }
         _loc10_ = new BattleMove(param2,0,20);
         if(_loc10_.pathToRect(param3.rect,true,_loc9_))
         {
            param4.debug("Op_MoveToRange too far moving in to as close as possible " + param3);
            return _loc10_;
         }
         return null;
      }
      
      public function listenForWillpower() : void
      {
         if(entity)
         {
            entity.stats.getStat(StatType.WILLPOWER).addEventListener("StatEvent.CHANGE",entityWillpowerHandler);
         }
      }
      
      public function unlistenForWillpower() : void
      {
         if(entity)
         {
            entity.stats.getStat(StatType.WILLPOWER).removeEventListener("StatEvent.CHANGE",entityWillpowerHandler);
         }
      }
      
      public function cleanup() : void
      {
         unlistenForWillpower();
         _entity = null;
         steps = null;
         flood = null;
         _path = null;
      }
      
      private function entityWillpowerHandler(param1:StatEvent) : void
      {
      }
      
      override public function toString() : String
      {
         return "[" + entity.id + " " + first + " -> " + last + "]";
      }
      
      public function copy(param1:BattleMove) : void
      {
         if(committed)
         {
            throw new IllegalOperationError("BattleMove.copy already committed " + this);
         }
         if(param1.entity != this.entity)
         {
            throw new ArgumentError("BattleMove.copy incompatible entities");
         }
         if(param1.first != entity.tile)
         {
            throw new IllegalOperationError("BattleMove.copy " + this + " bad tiles " + steps + " should start with " + entity.tile);
         }
         steps = param1.steps.concat();
         _executed = false;
         _executing = false;
         _committed = false;
      }
      
      public function equals(param1:BattleMove) : Boolean
      {
         var _loc2_:int = 0;
         if(steps.length == param1.steps.length)
         {
            _loc2_ = 0;
            while(_loc2_ < steps.length)
            {
               if(!steps[_loc2_].equals(param1.steps[_loc2_]))
               {
                  return false;
               }
               _loc2_++;
            }
            return true;
         }
         return false;
      }
      
      public function get forcedMove() : Boolean
      {
         return _forcedMove;
      }
      
      public function set forcedMove(param1:Boolean) : void
      {
         _forcedMove = param1;
      }
      
      public function get reactToEntityIntersect() : Boolean
      {
         return _reactToEntityIntersect;
      }
      
      public function set reactToEntityIntersect(param1:Boolean) : void
      {
         _reactToEntityIntersect = param1;
      }
      
      public function get numSteps() : int
      {
         return steps.length;
      }
      
      public function getStep(param1:int) : Tile
      {
         return steps[param1];
      }
      
      public function addStep(param1:Tile) : void
      {
         steps.push(param1);
      }
      
      public function get first() : Tile
      {
         return steps[0];
      }
      
      public function get last() : Tile
      {
         return steps[steps.length - 1];
      }
      
      public function getStepIndex(param1:Tile) : int
      {
         return steps.indexOf(param1);
      }
      
      public function hasStep(param1:Tile) : Boolean
      {
         return steps.indexOf(param1) >= 0;
      }
      
      public function get executed() : Boolean
      {
         return _executed;
      }
      
      public function setExecuted() : void
      {
         if(!_committed)
         {
            setCommitted("BattleMove.setExecuted");
         }
         if(_executed)
         {
            throw new IllegalOperationError("already executed");
         }
         _executing = false;
         _executed = true;
         entity.logger.info("BattleMove EXECUTED " + this);
         dispatchEvent(new BattleMoveEvent("BattleMoveEvent.EXECUTED"));
      }
      
      public function get committed() : Boolean
      {
         return _committed;
      }
      
      public function setCommitted(param1:String) : void
      {
         if(_committed)
         {
            throw new IllegalOperationError("already committed");
         }
         if(first != entity.tile)
         {
            throw new IllegalOperationError("Attempt to teleport " + entity + " to " + first);
         }
         entity.logger.debug("BattleMove.setCommitted " + this + " reason=" + param1);
         _committed = true;
         dispatchEvent(new BattleMoveEvent("BattleMoveEvent.COMMITTED"));
      }
      
      public function get path() : IPath
      {
         return _path;
      }
      
      private function setPath(param1:IPath) : void
      {
         if(committed)
         {
            throw new IllegalOperationError("BattleMove.setPath already committed " + this);
         }
         if(_path == param1)
         {
            return;
         }
         if(_path)
         {
            _path.dispatcher.removeEventListener("EVENT_PATH_STATUS_CHANGED",pathStatusChangedHandler);
            _path.status = PathStatus.TERMINATE;
            _path = null;
         }
         _path = param1;
         if(_path)
         {
            _path.dispatcher.addEventListener("EVENT_PATH_STATUS_CHANGED",pathStatusChangedHandler);
         }
      }
      
      public function reset(param1:Tile) : void
      {
         if(!param1)
         {
            throw new ArgumentError("uuuuuuhhhh");
         }
         setPath(null);
         if(param1 != entity.tile)
         {
            throw new IllegalOperationError("BattleMove.reset " + this + " invalid tile " + param1);
         }
         if(committed)
         {
            throw new IllegalOperationError("BattleMove.reset already committed " + this);
         }
         steps.splice(0,steps.length,param1);
         setWayPoint(param1);
         updateFloods();
         handlePlanChanged(false);
      }
      
      public function setWayPoint(param1:Tile) : void
      {
         if(param1 && param1 != last)
         {
            throw new IllegalOperationError("bad waypoint");
         }
         if(committed)
         {
            throw new IllegalOperationError("BattleMove.setWayPoint Attempt to modify committed move " + this);
         }
         wayPointSteps = numSteps;
         wayPointTile = param1;
         updateFloods();
         dispatchEvent(new BattleMoveEvent("BattleMoveEvent.WAYPOINT"));
      }
      
      public function trimStepsToWaypoint() : void
      {
         if(wayPointSteps < steps.length)
         {
            steps.splice(wayPointSteps,steps.length);
            handlePlanChanged(true);
         }
      }
      
      public function trimStepsTo(param1:int) : void
      {
         if(param1 < steps.length - 1)
         {
            steps.splice(param1 + 1,steps.length - param1 - 1);
         }
         handlePlanChanged(true);
      }
      
      public function trimStepsInLoop(param1:Tile) : Boolean
      {
         var _loc2_:int = steps.indexOf(param1);
         if(_loc2_ >= 0)
         {
            if(_loc2_ < steps.length - 1)
            {
               steps.splice(_loc2_ + 1,steps.length - _loc2_);
            }
            handlePlanChanged(true);
            return true;
         }
         return false;
      }
      
      public function pathToDiamond(param1:TileRect, param2:int, param3:int, param4:Boolean, param5:int) : Boolean
      {
         var _loc9_:Tile = null;
         var _loc6_:PathFloodSolverNode = null;
         if(param3 < 0)
         {
            throw new ArgumentError("No need to path when maxDist < 0");
         }
         var _loc8_:TileRect = new TileRect(last.location,entity.width,entity.length);
         var _loc10_:TileDiamond = new TileDiamond(param1,param2,param3,_loc8_,param5);
         if(_loc10_.hugs.indexOf(last.location) >= 0)
         {
            return true;
         }
         for each(var _loc7_ in _loc10_.hugs)
         {
            _loc9_ = entity.board.tiles.getTile(_loc7_.x,_loc7_.y);
            _loc6_ = flood.resultSet[_loc9_];
            if(_loc6_)
            {
               process(_loc9_,param4);
               if(numSteps > param5 + 1)
               {
                  trimStepsTo(param5);
               }
               return true;
            }
         }
         if(numSteps > 1)
         {
            reset(steps[0]);
            return pathToDiamond(param1,param2,param3,param4,param5);
         }
         return false;
      }
      
      public function pathToRect(param1:TileRect, param2:Boolean, param3:int) : Boolean
      {
         var _loc6_:Tile = null;
         var _loc4_:PathFloodSolverNode = null;
         var _loc7_:TileRectHugger = new TileRectHugger(new TileRect(last.location,entity.width,entity.length),param1);
         if(_loc7_.hugs.indexOf(last.location) >= 0)
         {
            return true;
         }
         for each(var _loc5_ in _loc7_.hugs)
         {
            _loc6_ = entity.board.tiles.getTile(_loc5_.x,_loc5_.y);
            _loc4_ = flood.resultSet[_loc6_];
            if(_loc4_)
            {
               process(_loc6_,param2);
               if(numSteps > param3 + 1)
               {
                  trimStepsTo(param3);
               }
               return true;
            }
         }
         if(numSteps > 1)
         {
            reset(steps[0]);
            return pathToRect(param1,param2,param3);
         }
         return false;
      }
      
      public function process(param1:Tile, param2:Boolean) : void
      {
         var _loc10_:IPath = null;
         var _loc9_:int = 0;
         var _loc4_:IPathGraphLink = null;
         var _loc3_:IBattleEntity = null;
         var _loc6_:int = 0;
         var _loc5_:int = 0;
         if(!param1)
         {
            throw new ArgumentError("uuuuuuhhhh");
         }
         if(committed)
         {
            throw new ArgumentError("Can\'t process when turn has already been commited.");
         }
         if(param1 == last)
         {
            return;
         }
         if(param2)
         {
            if(trimStepsInLoop(param1))
            {
               return;
            }
         }
         var _loc7_:int = int(steps.length);
         var _loc8_:IPathGraphNode = entity.board.tiles.pathGraph.getNode(param1);
         trimStepsToWaypoint();
         _loc10_ = flood.reconstructPathTo(_loc8_);
         if(!_loc10_)
         {
            return;
         }
         if(_loc10_.status == PathStatus.COMPLETE)
         {
            _loc9_ = 0;
            while(_loc9_ < _loc10_.links.length)
            {
               _loc4_ = _loc10_.links[_loc9_];
               steps.push(_loc4_.dst.key);
               _loc9_++;
            }
         }
         if(_loc7_ > 1)
         {
            _loc3_ = entity;
            _loc6_ = Math.min(_loc3_.stats.getStat(StatType.EXERTION).value,_loc3_.stats.getStat(StatType.WILLPOWER).value);
            _loc5_ = _loc3_.stats.getStat(StatType.MOVEMENT).value + _loc6_;
            if(steps.length > _loc5_ + 1)
            {
               reset(steps[0]);
               updateFloods();
               process(param1,param2);
               return;
            }
         }
         if(param2)
         {
            trimLoops();
         }
         handlePlanChanged(true);
      }
      
      private function trimLoops() : void
      {
         var _loc3_:int = 0;
         var _loc1_:Tile = null;
         var _loc2_:int = 0;
         _loc3_ = 0;
         while(_loc3_ < steps.length - 1)
         {
            _loc1_ = steps[_loc3_];
            _loc2_ = steps.indexOf(_loc1_,_loc3_ + 1);
            if(_loc2_ > _loc3_)
            {
               steps.splice(_loc3_ + 1,_loc2_ - _loc3_);
            }
            _loc3_++;
         }
      }
      
      protected function pathStatusChangedHandler(param1:PathEvent) : void
      {
         var _loc3_:int = 0;
         var _loc2_:IPathGraphLink = null;
         if(param1.path != path)
         {
            throw new IllegalOperationError("balls");
         }
         if(path.status == PathStatus.WAITING || path.status == PathStatus.WORKING)
         {
            return;
         }
         if(path.status == PathStatus.COMPLETE)
         {
            _loc3_ = 0;
            while(_loc3_ < path.links.length)
            {
               _loc2_ = path.links[_loc3_];
               steps.push(_loc2_.dst.key);
               _loc3_++;
            }
         }
         setPath(null);
         handlePlanChanged(true);
      }
      
      public function getFlood(param1:Tile, param2:int, param3:Boolean) : PathFloodSolver
      {
         var _loc6_:IPathGraphNode = null;
         var _loc4_:NodeBlockedChecker = null;
         var _loc5_:* = null;
         if(param1)
         {
            _loc6_ = entity.board.tiles.pathGraph.getNode(param1);
            _loc4_ = new NodeBlockedChecker(this);
            _loc4_.stepsBlock = param3;
            return new PathFloodSolver(_loc6_,heuristicFloodDistance,_loc4_.nodeBlockedFunc,param2);
         }
         return null;
      }
      
      private function handlePlanChanged(param1:Boolean) : void
      {
         var _loc8_:IPathGraphNode = null;
         var _loc7_:IPathGraphNode = null;
         var _loc5_:Path = null;
         var _loc10_:IPathGraphNode = null;
         var _loc9_:int = 0;
         var _loc2_:Tile = null;
         var _loc6_:IPathGraphNode = null;
         var _loc4_:IPathGraphLink = null;
         var _loc3_:IBattleEntity = entity;
         if(_loc3_)
         {
            updateFloods();
         }
         else
         {
            flood = null;
         }
         if(steps.length > 1)
         {
            _loc8_ = entity.board.tiles.pathGraph.getNode(first);
            _loc7_ = entity.board.tiles.pathGraph.getNode(last);
            _loc5_ = new Path(_loc8_,_loc7_);
            _loc10_ = _loc8_;
            _loc9_ = 1;
            while(_loc9_ < steps.length)
            {
               _loc2_ = steps[_loc9_];
               _loc6_ = entity.board.tiles.pathGraph.getNode(_loc2_);
               _loc4_ = _loc10_.getLink(_loc6_);
               _loc5_.links.push(_loc4_);
               _loc10_ = _loc6_;
               _loc9_++;
            }
            _loc5_.status = PathStatus.COMPLETE;
            setPath(_loc5_);
         }
         else
         {
            setPath(null);
         }
         dispatchEvent(new BattleMoveEvent("BattleMoveEvent.MOVE_CHANGED"));
      }
      
      public function updateFloods() : void
      {
         var _loc2_:IBattleEntity = entity;
         if(!_loc2_)
         {
            return;
         }
         var _loc3_:int = _loc2_.stats.getValue(StatType.MOVEMENT) - wayPointSteps + 1;
         var _loc5_:int = Math.min(_loc2_.stats.getValue(StatType.EXERTION),_loc2_.stats.getValue(StatType.WILLPOWER));
         var _loc4_:int = _loc3_ + Math.max(0,Math.min(_maxStars,_loc5_));
         _loc4_ = _loc4_ + _searchBonus;
         var _loc1_:Tile = wayPointTile;
         if(!_loc1_)
         {
            _loc1_ = first;
         }
         if(flood)
         {
            if(flood.src.key == _loc1_)
            {
               if(flood.costLimit == _loc4_)
               {
                  return;
               }
            }
         }
         flood = getFlood(_loc1_,_loc4_,true);
         flood.update(-1,null);
         dispatchEvent(new BattleMoveEvent("BattleMoveEvent.FLOOD_CHANGED"));
      }
      
      public function isInRange(param1:Tile) : Boolean
      {
         if(flood)
         {
            return flood.inResultSet(param1);
         }
         return false;
      }
      
      public function get executing() : Boolean
      {
         return _executing;
      }
      
      public function setExecuting() : void
      {
         _executing = true;
         dispatchEvent(new BattleMoveEvent("BattleMoveEvent.EXECUTING"));
      }
      
      public function get interrupted() : Boolean
      {
         return _interrupted;
      }
      
      public function setInterrupted() : void
      {
         _interrupted = true;
         dispatchEvent(new BattleMoveEvent("BattleMoveEvent.INTERRUPTED"));
      }
      
      public function handleIntersectEntity() : void
      {
         dispatchEvent(new BattleMoveEvent("BattleMoveEvent.INTERSECT_ENTITY"));
      }
      
      public function get entity() : IBattleEntity
      {
         return _entity;
      }
   }
}

import engine.battle.board.model.IBattleEntity;
import engine.path.IPathGraphNode;
import engine.tile.Tile;
import engine.tile.Tiles;
// JPEXS artifact fix: file-internal classes (after the package block) don't inherit its imports.
import engine.battle.fsm.BattleMove;

class NodeBlockedChecker
{
   
   public var stepsBlock:Boolean;
   
   public var move:BattleMove;
   
   public function NodeBlockedChecker(param1:BattleMove)
   {
      super();
      this.move = param1;
   }
   
   public function nodeBlockedFunc(param1:IPathGraphNode) : Boolean
   {
      var _loc5_:int = 0;
      var _loc4_:Tile = param1.key as Tile;
      var _loc2_:Tiles = move.entity.board.tiles;
      var _loc3_:IBattleEntity = move.entity as IBattleEntity;
      if(_loc2_.isTileBlockedForEntity(_loc3_,_loc4_))
      {
         return true;
      }
      if(stepsBlock)
      {
         _loc5_ = 0;
         while(_loc5_ < move.numSteps)
         {
            if(_loc4_ == move.getStep(_loc5_))
            {
               return true;
            }
            _loc5_++;
         }
      }
      return false;
   }
}
