package engine.resource
{
   import flash.errors.IllegalOperationError;
   import flash.events.Event;
   
   public class ResourceTree
   {
      
      public var children:Vector.<ChildInfo> = new Vector.<ChildInfo>();
      
      public var root:Resource;
      
      public var rootLoaded:Boolean;
      
      public function ResourceTree(param1:Resource)
      {
         super();
         if(null == param1)
         {
            throw new ArgumentError("null root");
         }
         this.root = param1;
      }
      
      protected function childResourceCompleteHandler(param1:Event) : void
      {
         checkChildren();
      }
      
      public function handleRootResourceLoadComplete() : void
      {
         if(rootLoaded)
         {
            throw new IllegalOperationError("Attempting to in-place reload the root of an ResourceTree.  This is currently not supported");
         }
         rootLoaded = true;
         for each(var _loc1_ in children)
         {
            _loc1_.startLoad();
         }
         checkChildren();
      }
      
      public function checkChildren() : void
      {
         if(!rootLoaded)
         {
            return;
         }
         for each(var _loc1_ in children)
         {
            if(!_loc1_.loaded)
            {
               return;
            }
         }
         root.loaded = true;
      }
      
      public function release() : void
      {
         for each(var _loc1_ in children)
         {
            _loc1_.release();
         }
      }
      
      internal function addChild(param1:String, param2:Class) : void
      {
         var _loc3_:ChildInfo = new ChildInfo(this,param1,param2);
         children.push(_loc3_);
         if(rootLoaded)
         {
            _loc3_.startLoad();
            checkChildren();
         }
      }
   }
}

import engine.resource.loader.IResourceLoader;
import flash.errors.IllegalOperationError;
import flash.events.Event;
// JPEXS artifact fix: file-internal classes (after the package block) don't inherit its imports.
import engine.resource.Resource;
import engine.resource.ResourceTree;

class ChildInfo
{
   
   public var clazz:Class;
   
   public var url:String;
   
   public var resource:Resource;
   
   public var tree:ResourceTree;
   
   public function ChildInfo(param1:ResourceTree, param2:String, param3:Class)
   {
      super();
      this.tree = param1;
      this.url = param2;
      this.clazz = param3;
   }
   
   public function startLoad() : void
   {
      if(resource)
      {
         throw new IllegalOperationError("double load");
      }
      resource = tree.root.resourceManager.getResource(url,clazz,null,null);
      resource.addEventListener("complete",childResourceCompleteHandler);
   }
   
   public function release() : void
   {
      if(resource)
      {
         resource.removeEventListener("complete",childResourceCompleteHandler);
         resource.refcount.releaseReference();
      }
   }
   
   protected function childResourceCompleteHandler(param1:Event) : void
   {
      tree.checkChildren();
   }
   
   public function get loaded() : Boolean
   {
      return resource && resource.loaded;
   }
   
   public function get loading() : Boolean
   {
      return resource && !resource.loaded;
   }
   
   public function get loader() : IResourceLoader
   {
      return resource ? resource.loader : null;
   }
}
