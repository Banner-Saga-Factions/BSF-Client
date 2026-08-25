package engine.resource.loader
{
   import engine.core.logging.ILogger;
   import engine.core.util.SwfHelper;
   import flash.display.DisplayObject;
   import flash.display.Loader;
   import flash.events.Event;
   import flash.events.HTTPStatusEvent;
   import flash.events.IOErrorEvent;
   import flash.events.ProgressEvent;
   import flash.system.ApplicationDomain;
   import flash.system.LoaderContext;
   import flash.system.SecurityDomain;
   import flash.utils.ByteArray;
   
   public class DisplayResourceLoader extends IDisplayResourceLoader
   {
      
      private var _logger:ILogger;
      
      public var loader:Loader = new Loader();
      
      public var urlResourceLoader:URLResourceLoader;
      
      public function DisplayResourceLoader(param1:String, param2:Function, param3:ILogger)
      {
         super(param1,param2,param3);
         _logger = param3;
         try
         {
            urlResourceLoader = new URLResourceLoader(param1,urlResourceLoaderCompleteHandler,param3,true);
         }
         catch(error:Error)
         {
            param3.error("DisplayResourceLoader proxy failed " + param1 + ": " + error);
            emitCompleteCallback(false);
         }
      }
      
      private function urlResourceLoaderCompleteHandler(param1:URLResourceLoader) : void
      {
         var _loc3_:ByteArray = null;
         var _loc5_:ApplicationDomain = null;
         var _loc4_:SecurityDomain = null;
         var _loc2_:LoaderContext = null;
         if(error)
         {
            logger.error("DisplayResourceLoader proxy failed: " + url);
            emitCompleteCallback(false);
            return;
         }
         try
         {
            _loc3_ = urlResourceLoader.data as ByteArray;
            if(_loc3_.length <= 0)
            {
               logger.error("DisplayResourceLoader proxy ZERO BYTES " + url);
               emitCompleteCallback(false);
               return;
            }
            // [Inference] BSF-Client #12 finding #2 ("Crash A"): battle_initiative.swf ships its own
            // older, UNGUARDED copies of GuiInitiative + GuiUtil. Loaded into a fresh private domain
            // (null) they win, so a null child in the initiative deploy branch throws #1009 inside
            // GuiUtil.updateDisplayList and kills the battle HUD.
            // Fix: route ONLY battle_initiative.swf through ApplicationDomain.currentDomain (scoped by
            // URL so town/map/popups keep their isolated-domain behavior). allowCodeImport stays true.
            // OBSERVED (2026-06-23 logs, ~4 battles, 0 #1009): the gui-SWF GuiInitiative SYMBOL still
            // binds to its own copy (it still logs), but GuiUtil -- referenced BY NAME -- resolves to our
            // guarded app.game.air.swf copy and absorbs the null child, which is what stops Crash A.
            // See ~/.claude/plans/review-bsf-client-misc-plan-fix-issue-12-clever-storm.md.
            //
            // DO NOT "escalate to allowCodeImport=false" -- an earlier version of this note suggested
            // it; MEASURED 2026-08-24, it cannot work. allowCodeImport=false makes loadBytes REFUSE any
            // SWF containing code (SecurityError #3226), and a code-bearing SWF is precisely what this
            // is: the initiative bar then never loads at all (BattleHudPageLoadHelper FAILED) and the
            // battle stalls in Deploy. Also measured and also worse: loading into a CHILD of
            // currentDomain (new ApplicationDomain(currentDomain)) brings Crash A straight back, because
            // a child resolves a name it defines ITSELF locally and only walks up to the parent for
            // names it lacks -- so the SWF's own stale GuiUtil wins again. Loading INTO currentDomain
            // works precisely because duplicate definitions are discarded in favour of the app's.
            //
            // The cost of that choice is the versus-path #1034 (see Plan-Issue-12 3.5b): the initiative
            // symbol still arrives as a class the app-side GuiBattleHud's concrete-typed field will not
            // accept. Fix that in GuiBattleHud (app code, ours to patch), NOT by changing the domain.
            _loc5_ = url.indexOf("battle_initiative.swf") != -1 ? ApplicationDomain.currentDomain : null;
            _loc4_ = null;
            _loc2_ = new LoaderContext(false,_loc5_,_loc4_);
            _loc2_.allowCodeImport = true;
            loader.contentLoaderInfo.addEventListener("init",onLoadInit);
            loader.contentLoaderInfo.addEventListener("open",onLoadOpen);
            loader.contentLoaderInfo.addEventListener("complete",onLoadComplete);
            loader.contentLoaderInfo.addEventListener("ioError",onLoadFailed);
            loader.contentLoaderInfo.addEventListener("unload",loaderInfoUnloadHandler);
            loader.contentLoaderInfo.addEventListener("progress",loaderInfoProgressHandler);
            loader.contentLoaderInfo.addEventListener("httpStatus",loaderInfoHttpStatusHandler);
            loader.contentLoaderInfo.addEventListener("deactivate",loaderInfoDeactivateHandler);
            if(url.indexOf(".swf") == url.length - 4)
            {
               if(!SwfHelper.checkSwfStructure(_loc3_,url,logger))
               {
                  emitCompleteCallback(false);
                  return;
               }
            }
            loader.loadBytes(_loc3_,_loc2_);
            urlResourceLoader.unload();
            urlResourceLoader = null;
         }
         catch(error:Error)
         {
            logger.error("DisplayResourceLoader proxy unpack failed " + url + ": " + error + "\n" + error.getStackTrace());
            emitCompleteCallback(false);
         }
      }
      
      protected function loaderInfoDeactivateHandler(param1:Event) : void
      {
      }
      
      protected function loaderInfoHttpStatusHandler(param1:HTTPStatusEvent) : void
      {
      }
      
      protected function loaderInfoProgressHandler(param1:ProgressEvent) : void
      {
      }
      
      protected function loaderInfoUnloadHandler(param1:Event) : void
      {
      }
      
      private function onLoadInit(param1:Event) : void
      {
      }
      
      private function onLoadOpen(param1:Event) : void
      {
      }
      
      private function onLoadComplete(param1:Event) : void
      {
         unlisten();
         emitCompleteCallback(true);
      }
      
      private function onLoadFailed(param1:IOErrorEvent) : void
      {
         logger.error("DisplayResourceLoader onLoadFailed proxy loadBytes " + url + " " + param1.text);
         unlisten();
         emitCompleteCallback(false);
      }
      
      private function unlisten() : void
      {
         loader.contentLoaderInfo.removeEventListener("complete",onLoadComplete);
         loader.contentLoaderInfo.removeEventListener("ioError",onLoadFailed);
      }
      
      override public function unload() : void
      {
         loader.unloadAndStop();
         loader = null;
      }
      
      override public function get content() : DisplayObject
      {
         return loader.content;
      }
      
      override public function get data() : *
      {
         return content;
      }
      
      override public function getLibraryClass(param1:String) : Class
      {
         if(null == loader)
         {
            return null;
         }
         var _loc2_:ApplicationDomain = loader.contentLoaderInfo.applicationDomain;
         if(null == _loc2_)
         {
            return null;
         }
         if(!_loc2_.hasDefinition(param1))
         {
            logger.error("SWF " + url + " is missing class " + param1);
            return null;
         }
         return _loc2_.getDefinition(param1) as Class;
      }
   }
}

