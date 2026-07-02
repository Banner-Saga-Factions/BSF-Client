package engine.tile
{
   import engine.battle.ability.def.IBattleAbilityDef;
   import engine.battle.ability.effect.model.Effect;
   import engine.path.IPath;
   import engine.path.IPathGraph;
   import engine.tile.def.TileDef;
   import engine.tile.def.TileLocation;
   import engine.tile.def.TileLocationArea;
   import engine.tile.def.TileRect;
   import flash.events.EventDispatcher;
   import flash.geom.Rectangle;
   import flash.utils.Dictionary;
   
   public class Tiles extends EventDispatcher
   {
      
      public var tiles:Vector.<Tile>;
      
      public var tilesByLocation:Dictionary;
      
      public var pathGraph:IPathGraph;
      
      private var entityPositions:Dictionary;
      
      private var nodeBlockedCheckers:Dictionary;
      
      public var flyText:String;
      
      public var flyTextColor:uint;
      
      public var flyTextTile:Tile;
      
      public var flyTextFontName:String;
      
      public var flyTextFontSize:int;
      
      public function Tiles(param1:TileLocationArea, param2:TileLocationArea)
      {
         var _loc3_:Tile = null;
         var _loc4_:* = null;
         tiles = new Vector.<Tile>();
         tilesByLocation = new Dictionary();
         entityPositions = new Dictionary();
         nodeBlockedCheckers = new Dictionary(true);
         super();
         for each(_loc4_ in param1.locations)
         {
            if(getTileByLocation(_loc4_))
            {
               throw new ArgumentError("Already exists: " + _loc4_);
            }
            _loc3_ = createTile(_loc4_.x,_loc4_.y,true);
            tilesByLocation[_loc4_] = _loc3_;
            tiles.push(_loc3_);
         }
         for each(_loc4_ in param2.locations)
         {
            if(getTileByLocation(_loc4_))
            {
               throw new ArgumentError("Already exists: " + _loc4_);
            }
            _loc3_ = createTile(_loc4_.x,_loc4_.y,false);
            tilesByLocation[_loc4_] = _loc3_;
            tiles.push(_loc3_);
         }
         pathGraph = createPathGraph();
      }
      
      protected function createTile(param1:int, param2:int, param3:Boolean) : Tile
      {
         return new Tile(new TileDef(param1,param2,param3),this);
      }
      
      protected function createPathGraph() : IPathGraph
      {
         return null;
      }
      
      public function addTrigger(param1:TileRect, param2:Function, param3:Boolean, param4:Object, param5:Effect) : TileTrigger
      {
         return null;
      }
      
      public function addAbilityBasedTrigger(param1:TileRect, param2:IBattleAbilityDef, param3:Boolean) : TileTrigger
      {
         return null;
      }
      
      public function removeTrigger(param1:TileTrigger) : void
      {
      }
      
      private function updateEntityTiles(param1:ITileResident, param2:Rectangle, param3:Boolean) : void
      {
         var _loc4_:int = 0;
         var _loc6_:int = 0;
         var _loc5_:Tile = null;
         _loc4_ = 0;
         while(_loc4_ < param2.width)
         {
            _loc6_ = 0;
            while(_loc6_ < param2.height)
            {
               _loc5_ = getTile(param2.x + _loc4_,param2.y + _loc6_);
               if(_loc5_)
               {
                  if(!param3)
                  {
                     _loc5_.removeResident(param1);
                  }
                  else
                  {
                     _loc5_.addResident(param1);
                  }
               }
               _loc6_++;
            }
            _loc4_++;
         }
      }
      
      final protected function blockTilesForEntity(param1:ITileResident) : void
      {
         if(!param1)
         {
            return;
         }
         var _loc2_:Rectangle = entityPositions[param1];
         if(_loc2_)
         {
            updateEntityTiles(param1,_loc2_,false);
         }
         else
         {
            _loc2_ = new Rectangle();
         }
         if(param1.tiles != this)
         {
            return;
         }
         _loc2_.setTo(param1.x,param1.y,param1.width,param1.length);
         updateEntityTiles(param1,_loc2_,true);
         entityPositions[param1] = _loc2_;
      }
      
      public function getTileByLocation(param1:TileLocation) : Tile
      {
         return param1 ? tilesByLocation[param1] : null;
      }
      
      public function getTile(param1:int, param2:int) : Tile
      {
         return getTileByLocation(TileLocation.fetch(param1,param2));
      }
      
      public function getPath(param1:ITileResident, param2:int, param3:int) : IPath
      {
         var _loc6_:Tile = param1.tile;
         var _loc5_:Tile = getTile(param2,param3);
         if(_loc6_ == _loc5_ || _loc6_ == null || _loc5_ == null)
         {
            return null;
         }
         var _loc4_:NodeBlockedChecker = getNodeBlockedChecker(param1);
         return pathGraph.getPath(_loc6_,_loc5_,_loc4_.nodeBlockedFunc);
      }
      
      private function getNodeBlockedChecker(param1:ITileResident) : NodeBlockedChecker
      {
         var _loc2_:NodeBlockedChecker = nodeBlockedCheckers[param1];
         if(!_loc2_)
         {
            _loc2_ = new NodeBlockedChecker(this,param1);
            nodeBlockedCheckers[param1] = _loc2_;
         }
         return _loc2_;
      }
      
      public function isTileBlockedForEntity(param1:ITileResident, param2:Tile) : Boolean
      {
         var _loc5_:int = 0;
         var _loc4_:int = 0;
         var _loc3_:Tile = null;
         _loc5_ = 0;
         while(_loc5_ < param1.width)
         {
            _loc4_ = 0;
            while(_loc4_ < param1.length)
            {
               _loc3_ = getTile(param2.def.x + _loc5_,param2.def.y + _loc4_);
               if(_loc3_ == null)
               {
                  return true;
               }
               if(!_loc3_.hasResident(param1) && _loc3_.numResidents > 0)
               {
                  return true;
               }
               _loc4_++;
            }
            _loc5_++;
         }
         return false;
      }
      
      public function emitFlyText(param1:Tile, param2:String, param3:uint, param4:String, param5:int) : void
      {
         flyTextTile = param1;
         flyText = param2;
         flyTextColor = param3;
         flyTextFontName = param4;
         flyTextFontSize = param5;
         dispatchEvent(new TilesEvent("TilesEvent.TILE_FLYTEXT"));
      }
   }
}

import engine.path.IPathGraphNode;
// JPEXS artifact fix: file-internal classes (after the package block) don't inherit its imports.
import engine.tile.ITileResident;
import engine.tile.Tile;
import engine.tile.Tiles;

class NodeBlockedChecker
{
   
   public var entity:ITileResident;
   
   public var tiles:Tiles;
   
   public function NodeBlockedChecker(param1:Tiles, param2:ITileResident)
   {
      super();
      this.entity = param2;
      this.tiles = param1;
   }
   
   public function nodeBlockedFunc(param1:IPathGraphNode) : Boolean
   {
      var _loc2_:Tile = param1.key as Tile;
      return tiles.isTileBlockedForEntity(entity,_loc2_);
   }
}
