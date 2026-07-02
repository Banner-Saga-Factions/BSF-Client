package engine.landscape.view
{
   import engine.anim.def.AnimClipDef;
   import engine.anim.view.AnimClip;
   import engine.anim.view.AnimClipSprite;
   import engine.core.cmd.CmdExec;
   import engine.core.cmd.ShellCmdManager;
   import engine.core.locale.LocaleCategory;
   import engine.core.logging.ILogger;
   import engine.core.render.BoundedCamera;
   import engine.gui.core.GuiLabel;
   import engine.gui.core.GuiSprite;
   import engine.landscape.def.LandscapeLayerDef;
   import engine.landscape.def.LandscapeLayerSpriteDef;
   import engine.landscape.model.Landscape;
   import engine.landscape.travel.view.TravelView;
   import engine.resource.AnimClipResource;
   import engine.resource.BitmapResource;
   import engine.resource.Resource;
   import engine.resource.ResourceGroup;
   import engine.resource.event.ResourceLoadedEvent;
   import engine.saga.SpeakEvent;
   import engine.saga.Variable;
   import engine.scene.view.SceneView;
   import flash.display.Bitmap;
   import flash.display.DisplayObject;
   import flash.display.Graphics;
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.EventDispatcher;
   import flash.geom.Point;
   import flash.geom.Rectangle;
   import flash.utils.Dictionary;
   
   public class LandscapeView extends GuiSprite
   {
      
      public static const EVENT_SHOW_ANCHORS:String = "LandscapeView.EVENT_SHOW_ANCHORS";
      
      private static var _showClickables:Boolean;
      
      public static var allowRandomLayers:Boolean = true;
      
      private static var _showClickablesDispatcher:EventDispatcher = new EventDispatcher();
      
      protected var layers:Vector.<LandscapeLayerDef>;
      
      protected var isFinished:Boolean;
      
      public var landscape:Landscape;
      
      private var spriteDef2Sprite:Dictionary;
      
      private var animPaths:Vector.<AnimPathView>;
      
      protected var spriteDef2Resource:Dictionary;
      
      protected var spriteDef2HoverResource:Dictionary;
      
      protected var waitingResources:Dictionary;
      
      public var layerDef2LayerSprite:Dictionary;
      
      public var resourceGroup:ResourceGroup;
      
      private var clickables:Vector.<ClickablePair>;
      
      private var clickablesByDef:Dictionary;
      
      private var helpSpritesByDef:Dictionary;
      
      private var guidepostsByDef:Dictionary;
      
      private var guidepostStates:Dictionary;
      
      private var _pressedClickable:LandscapeLayerSpriteDef;
      
      private var _hoverClickable:LandscapeLayerSpriteDef;
      
      private var _showHelp:Boolean;
      
      private var _showAnchors:Boolean = false;
      
      protected var landmarks:Shape;
      
      private var viewArea:Rectangle;
      
      public var shell:ShellCmdManager;
      
      public var clickableDefs:Vector.<LandscapeLayerSpriteDef>;
      
      protected var fogShape:Shape = null;
      
      public var travelView:TravelView;
      
      private var anims:Vector.<AnimClipSprite>;
      
      private var _clampParallax:Boolean = true;
      
      private var _enableParallax:Boolean = true;
      
      public var sceneView:SceneView;
      
      private var extras:Array;
      
      private var _spriteDefWaits:Dictionary;
      
      private var parallax_dx:Number = 0;
      
      private var parallax_dy:Number = 0;
      
      private var unclamped_dx:Number = 0;
      
      private var unclamped_dy:Number = 0;
      
      public function LandscapeView(param1:SceneView, param2:Landscape, param3:Number, param4:Number, param5:Boolean = false)
      {
         var _loc6_:String = null;
         layers = new Vector.<LandscapeLayerDef>();
         spriteDef2Sprite = new Dictionary();
         animPaths = new Vector.<AnimPathView>();
         spriteDef2Resource = new Dictionary();
         spriteDef2HoverResource = new Dictionary();
         waitingResources = new Dictionary();
         layerDef2LayerSprite = new Dictionary();
         resourceGroup = new ResourceGroup();
         clickables = new Vector.<ClickablePair>();
         clickablesByDef = new Dictionary();
         helpSpritesByDef = new Dictionary();
         guidepostsByDef = new Dictionary();
         guidepostStates = new Dictionary();
         landmarks = new Shape();
         viewArea = new Rectangle();
         clickableDefs = new Vector.<LandscapeLayerSpriteDef>();
         anims = new Vector.<AnimClipSprite>();
         extras = [];
         _spriteDefWaits = new Dictionary();
         super();
         _showClickablesDispatcher.addEventListener("change",showClickablesHandler);
         this.name = "landscape_view";
         this.sceneView = param1;
         this.landscape = param2;
         this.shell = new ShellCmdManager(param2.context.logger);
         if(param5 == false)
         {
            this.mouseEnabled = false;
            this.mouseChildren = false;
         }
         var _loc7_:Array = [];
         for each(var _loc8_ in param2.def.layers)
         {
            if(_loc8_.speed > param3 && _loc8_.speed <= param4)
            {
               if(allowRandomLayers)
               {
                  if(!checkLayer(_loc8_))
                  {
                     continue;
                  }
                  if(_loc6_ != _loc8_.randomGroup)
                  {
                     if(_loc7_.length > 0)
                     {
                        addLayerDef(pickOneLayer(_loc7_));
                     }
                     _loc7_ = [];
                     _loc6_ = null;
                  }
                  if(_loc8_.randomGroup)
                  {
                     _loc7_.push(_loc8_);
                     _loc6_ = _loc8_.randomGroup;
                     continue;
                  }
               }
               addLayerDef(_loc8_);
            }
         }
         if(_loc7_.length > 0)
         {
            addLayerDef(pickOneLayer(_loc7_));
         }
         finishLoading();
         param2.camera.addEventListener("EVENT_CAMERA_MOVED",cameraMovedHandler);
         param2.camera.addEventListener("EVENT_CAMERA_VIEW_CHANGED",cameraViewChangedHandler);
         shell.add("layer_list",shellCmdFuncLayerList);
         shell.add("layer_hide",shellCmdFuncLayerHide);
         shell.add("layer_show",shellCmdFuncLayerShow);
         if(param2.def.travel && param2.travel)
         {
            travelView = new TravelView(param2.travel,this);
            addChild(travelView);
         }
      }
      
      public static function get showClickables() : Boolean
      {
         return _showClickables;
      }
      
      public static function set showClickables(param1:Boolean) : void
      {
         _showClickables = param1;
         _showClickablesDispatcher.dispatchEvent(new Event("change"));
      }
      
      private function checkLayer(param1:LandscapeLayerDef) : Boolean
      {
         var _loc2_:Variable = null;
         var _loc3_:Variable = null;
         if(param1.ifCondition)
         {
            _loc2_ = landscape.context.saga.getVar(param1.ifCondition,null);
            if(!_loc2_ || !_loc2_.asBoolean)
            {
               logger.debug("checkLayer SKIP-IF " + param1 + " via " + _loc2_);
               return false;
            }
         }
         if(param1.notCondition)
         {
            _loc3_ = landscape.context.saga.getVar(param1.notCondition,null);
            if(_loc3_ && _loc3_.asBoolean)
            {
               logger.debug("checkLayer SKIP-NOT " + param1 + " via " + _loc3_);
               return false;
            }
         }
         return true;
      }
      
      private function pickOneLayer(param1:Array) : LandscapeLayerDef
      {
         return param1[Math.round((param1.length - 1) * Math.random())];
      }
      
      public function handleSpeak(param1:SpeakEvent, param2:String) : Boolean
      {
         var _loc6_:String = null;
         _loc6_ = "landscape.";
         var _loc8_:String = null;
         var _loc7_:LandscapeLayerSpriteDef = null;
         var _loc5_:Point = null;
         var _loc4_:MovieClip = null;
         var _loc3_:Sprite = null;
         if(!landscape || !landscape.def)
         {
            logger.error("Speaking into dead scene");
            return true;
         }
         if(travelView)
         {
            if(travelView.handleSpeak(param1,param2))
            {
               return true;
            }
         }
         if(param2 && param2.indexOf("landscape.") == 0)
         {
            _loc8_ = param2.substr("landscape.".length);
            _loc7_ = getSpriteDefFromPath(_loc8_);
            if(_loc7_)
            {
               _loc5_ = _loc7_.offset.clone();
               if(_loc5_)
               {
                  _loc4_ = landscape.scene.context.createSpeechBubble(param1);
                  if(_loc4_)
                  {
                     _loc4_.x = _loc5_.x;
                     _loc4_.y = _loc5_.y;
                     _loc3_ = layerDef2LayerSprite[_loc7_.layer];
                     _loc3_.addChild(_loc4_);
                  }
               }
            }
            return true;
         }
         return false;
      }
      
      private function getSpriteDefFromPath(param1:String) : LandscapeLayerSpriteDef
      {
         var _loc5_:String = null;
         var _loc3_:String = null;
         var _loc4_:LandscapeLayerSpriteDef = null;
         var _loc2_:LandscapeLayerDef = null;
         var _loc6_:int = param1.indexOf(".");
         if(_loc6_ < 0)
         {
            // JPEXS artifact fix: decompiler left raw AVM2 iterator opcodes (hasnext/nextvalue)
            // it could not lift back into a loop. Reconstructed as the equivalent for-each:
            // return the first layer whose getSprite(param1) is non-null (else null).
            for each(_loc2_ in layers)
            {
               _loc4_ = _loc2_.getSprite(param1);
               if(_loc4_)
               {
                  break;
               }
            }
            return _loc4_;
         }
         _loc5_ = param1.substring(0,_loc6_);
         _loc3_ = param1.substring(_loc6_ + 1);
         _loc2_ = landscape.def.getLayer(_loc5_);
         if(_loc2_)
         {
            return _loc2_.getSprite(_loc3_);
         }
         logger.error("No such layer: " + _loc5_);
         return null;
      }
      
      public function getAnchorPoint(param1:String) : Point
      {
         var _loc2_:Sprite = null;
         var _loc7_:int = param1.indexOf(".");
         var _loc6_:String = param1.substring(0,_loc7_);
         var _loc5_:String = param1.substring(_loc7_ + 1);
         var _loc4_:LandscapeLayerDef = landscape.def.getLayer(_loc6_);
         var _loc3_:Point = _loc4_.getPoint(_loc5_);
         if(_loc3_)
         {
            _loc2_ = layerDef2LayerSprite[_loc4_];
            if(_loc2_)
            {
               return new Point(_loc3_.x + _loc2_.x,_loc3_.y + _loc2_.y);
            }
         }
         return null;
      }
      
      public function update(param1:int) : void
      {
         for each(var _loc2_ in anims)
         {
            if(_loc2_.clip.playing)
            {
               _loc2_.clip.advance(param1);
               _loc2_.update();
            }
         }
         if(travelView)
         {
            travelView.update(param1);
         }
      }
      
      public function pause() : void
      {
      }
      
      public function resume() : void
      {
      }
      
      public function cleanup() : void
      {
         _showClickablesDispatcher.removeEventListener("change",showClickablesHandler);
         if(travelView)
         {
            travelView.cleanup();
         }
         removeAllChildren();
         landscape.camera.removeEventListener("EVENT_CAMERA_MOVED",cameraMovedHandler);
         landscape.camera.removeEventListener("EVENT_CAMERA_VIEW_CHANGED",cameraViewChangedHandler);
         for each(var _loc3_ in animPaths)
         {
            _loc3_.cleanup();
         }
         animPaths = null;
         for each(var _loc1_ in anims)
         {
            if(_loc1_.clip)
            {
               _loc1_.clip.stop();
               _loc1_.clip.cleanup();
            }
            _loc1_.cleanup();
         }
         anims = null;
         for each(var _loc2_ in waitingResources)
         {
            _loc2_.removeResourceListener(resourceCompleteHandler);
         }
         resourceGroup.release();
         spriteDef2Resource = null;
         spriteDef2HoverResource = null;
         waitingResources = null;
      }
      
      protected function cameraViewChangedHandler(param1:Event) : void
      {
         updateDelta();
      }
      
      protected function cameraMovedHandler(param1:Event) : void
      {
         updateDelta();
      }
      
      public function addLayerDef(param1:LandscapeLayerDef) : void
      {
         var _loc2_:Resource = null;
         var _loc5_:Resource = null;
         layers.push(param1);
         var _loc4_:Sprite = new Sprite();
         _loc4_.name = param1.nameId;
         addChild(_loc4_);
         _loc4_.x = param1.offset.x;
         _loc4_.y = param1.offset.y;
         layerDef2LayerSprite[param1] = _loc4_;
         if(param1.speed > camera.boundaryAdjustmentFactor)
         {
            camera.boundaryAdjustmentFactor = param1.speed;
         }
         for each(var _loc3_ in param1.layerSprites)
         {
            _loc2_ = getResourceForSpriteDef(_loc3_);
            if(_loc2_)
            {
               if(_loc2_.loaded)
               {
                  processResource(_loc2_);
               }
               else
               {
                  waitingResources[_loc2_] = _loc2_;
                  _loc2_.addEventListener("complete",resourceCompleteHandler);
               }
               if(_loc3_.hover)
               {
                  _loc5_ = getResourceForSpriteDefHover(_loc3_);
                  if(_loc5_.loaded)
                  {
                     processResource(_loc5_);
                  }
                  else
                  {
                     waitingResources[_loc5_] = _loc5_;
                     _loc5_.addEventListener("complete",resourceCompleteHandler);
                  }
               }
            }
         }
      }
      
      private function getResourceForSpriteDefHover(param1:LandscapeLayerSpriteDef) : Resource
      {
         var _loc2_:Resource = spriteDef2HoverResource[param1];
         if(!_loc2_)
         {
            if(param1.hover)
            {
               _loc2_ = landscape.context.resman.getResource(param1.hover,BitmapResource,resourceGroup);
            }
            spriteDef2HoverResource[param1] = _loc2_;
         }
         return _loc2_;
      }
      
      private function getResourceForSpriteDef(param1:LandscapeLayerSpriteDef) : Resource
      {
         var _loc2_:Resource = spriteDef2Resource[param1];
         if(!_loc2_)
         {
            if(param1.bmp)
            {
               _loc2_ = landscape.context.resman.getResource(param1.bmp,BitmapResource,resourceGroup);
            }
            else if(param1.anim)
            {
               _loc2_ = landscape.context.resman.getResource(param1.anim,AnimClipResource,resourceGroup);
            }
            spriteDef2Resource[param1] = _loc2_;
         }
         return _loc2_;
      }
      
      public function getLayerSprite(param1:String = null, param2:LandscapeLayerDef = null) : Sprite
      {
         var _loc4_:LandscapeLayerDef = null;
         var _loc3_:Sprite = null;
         if(param1 != null)
         {
            _loc4_ = landscape.def.getLayer(param1);
            _loc3_ = layerDef2LayerSprite[_loc4_];
         }
         else
         {
            _loc3_ = layerDef2LayerSprite[param2];
         }
         return _loc3_;
      }
      
      public function addExtraToLayer(param1:String, param2:Sprite) : Point
      {
         var _loc4_:Sprite = getLayerSprite(param1);
         if(!_loc4_)
         {
            throw new ArgumentError("Can\'t add to that layer: " + param1);
         }
         var _loc3_:LandscapeLayerDef = landscape.def.getLayer(param1);
         extras.push({
            "layerSprite":_loc4_,
            "sprite":param2
         });
         addExtrasToLayers();
         return _loc3_.offset;
      }
      
      public function addExtrasToLayers() : void
      {
         var _loc3_:Sprite = null;
         var _loc2_:Sprite = null;
         if(isFinished && extras.length > 0)
         {
            for each(var _loc1_ in extras)
            {
               _loc3_ = _loc1_.layerSprite;
               _loc2_ = _loc1_.sprite;
               if(_loc3_)
               {
                  _loc3_.addChild(_loc2_);
               }
            }
            extras = [];
         }
      }
      
      public function get camera() : BoundedCamera
      {
         return landscape ? landscape.camera : null;
      }
      
      protected function resourceCompleteHandler(param1:ResourceLoadedEvent) : void
      {
         processResource(param1.resource);
         finishLoading();
      }
      
      private function processResource(param1:Resource) : void
      {
         if(param1.loaded)
         {
            delete waitingResources[param1];
            param1.removeResourceListener(resourceCompleteHandler);
         }
      }
      
      public function handleSpriteDefAdded(param1:LandscapeLayerSpriteDef, param2:DisplayObject) : void
      {
      }
      
      protected function finishLoading() : void
      {
         if(isWaiting)
         {
            return;
         }
         if(isFinished)
         {
            return;
         }
         isFinished = true;
         for each(var _loc1_ in layers)
         {
            for each(var _loc2_ in _loc1_.layerSprites)
            {
               addSpriteDef(_loc2_,false);
            }
         }
         clickables.reverse();
         addExtrasToLayers();
         setupFog();
         updateDelta();
         updateAtmosphere();
      }
      
      private function setupFog() : void
      {
         if(landscape.def.hasFog == true)
         {
            fogShape = new Shape();
            addChild(fogShape);
            fogShape.graphics.beginFill(landscape.def.fogColor,landscape.def.fogAlpha);
            fogShape.graphics.drawRect(0 - camera.width / 2,0 - camera.height / 2,camera.width,camera.height);
            fogShape.graphics.endFill();
         }
      }
      
      private function waitForSpriteDef(param1:LandscapeLayerSpriteDef, param2:Resource) : void
      {
         if(!_spriteDefWaits[param2])
         {
            _spriteDefWaits[param2] = {
               "layer":param1.layer,
               "spriteDef":param1
            };
            param2.addResourceListener(spriteDefCompleteHandler);
         }
      }
      
      private function spriteDefCompleteHandler(param1:ResourceLoadedEvent) : void
      {
         var _loc2_:Object = null;
         if(param1.resource)
         {
            _loc2_ = _spriteDefWaits[param1.resource];
            if(_loc2_)
            {
               addSpriteDef(_loc2_.spriteDef,false);
            }
         }
      }
      
      protected function addSpriteDef(param1:LandscapeLayerSpriteDef, param2:Boolean) : DisplayObject
      {
         var _loc6_:Boolean = false;
         var _loc3_:ClickablePair = null;
         var _loc5_:AnimPathView = null;
         var _loc4_:Resource = spriteDef2Resource[param1];
         var _loc10_:Resource = spriteDef2HoverResource[param1];
         if(!_loc4_)
         {
            _loc4_ = getResourceForSpriteDef(param1);
         }
         if(param1.hover)
         {
            if(!_loc10_)
            {
               _loc10_ = getResourceForSpriteDefHover(param1);
            }
            if(!_loc10_.loaded)
            {
               if(param2)
               {
                  waitForSpriteDef(param1,_loc10_);
               }
               else
               {
                  logger.error("LandscapeView.addSpriteDef Could not create " + _loc10_.url + " synchronously");
               }
               return null;
            }
         }
         if(_loc4_ && !_loc4_.loaded)
         {
            if(param2)
            {
               waitForSpriteDef(param1,_loc4_);
            }
            else
            {
               logger.error("LandscapeView.addSpriteDef Could not create " + _loc4_.url + " synchronously");
            }
            return null;
         }
         var _loc8_:Sprite = layerDef2LayerSprite[param1.layer];
         if(!_loc8_)
         {
            logger.error("LandscapeView.addSpriteDef no such layer: " + param1.layer);
            return null;
         }
         var _loc7_:DisplayObject = generateSpriteDefDisplay(param1,spriteDef2Resource[param1]);
         var _loc9_:DisplayObject = null;
         if(_loc10_)
         {
            _loc9_ = generateSpriteDefDisplay(param1,spriteDef2HoverResource[param1]);
         }
         if(_loc7_)
         {
            if(param1.clickable)
            {
               _loc3_ = new ClickablePair(param1,_loc8_,_loc7_,_loc9_);
               clickables.push(_loc3_);
               clickableDefs.push(param1);
               clickablesByDef[param1] = _loc3_;
               _loc6_ = showClickables;
            }
            else if(param1.help)
            {
               helpSpritesByDef[param1] = _loc7_;
               _loc6_ = showHelp;
            }
            else if(param1.guidepost)
            {
               guidepostsByDef[param1] = _loc7_;
               if(param1.guidepost in guidepostStates)
               {
                  _loc6_ = Boolean(guidepostStates[param1.guidepost]);
               }
            }
            else
            {
               _loc6_ = true;
            }
            if(_loc6_)
            {
               spriteDef2Sprite[param1] = _loc7_;
               _loc8_.addChild(_loc7_);
            }
            handleSpriteDefAdded(param1,_loc7_);
            if(param1.debug)
            {
               _loc7_.opaqueBackground = 16711680;
            }
            if(param1.animPath)
            {
               _loc5_ = new AnimPathView(param1.animPath,_loc8_,_loc7_);
               animPaths.push(_loc5_);
               _loc5_.next();
            }
         }
         return _loc7_;
      }
      
      private function generateAnchor(param1:LandscapeLayerSpriteDef) : DisplayObject
      {
         if(!_showAnchors)
         {
            return null;
         }
         var _loc3_:Sprite = new Sprite();
         var _loc2_:Graphics = _loc3_.graphics;
         _loc2_.lineStyle(2,16711680);
         _loc2_.beginFill(16776960,0.8);
         _loc2_.drawCircle(0,0,9);
         _loc2_.endFill();
         _loc2_.lineStyle(3,16711680,1);
         _loc2_.drawCircle(0,-53,3);
         _loc2_.moveTo(0,4);
         _loc2_.lineTo(0,-50);
         _loc2_.moveTo(0,0);
         _loc2_.lineTo(-20,-20);
         _loc2_.lineTo(-20,-30);
         _loc2_.lineTo(-16,-26);
         _loc2_.moveTo(0,0);
         _loc2_.lineTo(20,-20);
         _loc2_.lineTo(20,-30);
         _loc2_.lineTo(16,-26);
         return _loc3_;
      }
      
      private function generateSpriteDefDisplay(param1:LandscapeLayerSpriteDef, param2:Resource) : DisplayObject
      {
         var _loc4_:DisplayObject = null;
         var _loc3_:BitmapResource = null;
         var _loc5_:AnimClipResource = null;
         if(param1.anchor)
         {
            _loc4_ = generateAnchor(param1);
            if(!_loc4_)
            {
               return null;
            }
         }
         else if(param2)
         {
            if(param2.error)
            {
               logger.error("in layer " + param1.layer.nameId + " skipping error sprite nameid:[" + param1.nameId + "] url:[" + param1.bmp + "]");
               return null;
            }
            _loc3_ = param2 as BitmapResource;
            if(_loc3_)
            {
               _loc4_ = generateBitmap(_loc3_,param1);
            }
            else
            {
               _loc5_ = param2 as AnimClipResource;
               if(_loc5_)
               {
                  _loc4_ = generateAnimClip(_loc5_,param1);
                  if(_loc4_)
                  {
                     anims.push(_loc4_);
                  }
               }
            }
         }
         _loc4_ = createSpriteLabel(_loc4_,param1);
         if(_loc4_)
         {
            updateSpriteDisplay(_loc4_,param1);
         }
         return _loc4_;
      }
      
      private function updateSpriteDisplay(param1:DisplayObject, param2:LandscapeLayerSpriteDef) : void
      {
         var _loc4_:GuiLabel = null;
         var _loc3_:Sprite = null;
         param1.name = "sprite_" + param2.nameId;
         param1.x = param2.offset.x;
         param1.y = param2.offset.y;
         if(param2.blendMode)
         {
            param1.blendMode = param2.blendMode;
         }
         else
         {
            param1.blendMode = "normal";
         }
         param1.scaleX = param2.scale.x;
         param1.scaleY = param2.scale.y;
         param1.rotation = param2.rotation;
         if(param2.label)
         {
            _loc4_ = param1 as GuiLabel;
            if(!_loc4_)
            {
               _loc3_ = param1 as Sprite;
               if(_loc3_ && _loc3_.numChildren > 1)
               {
                  _loc4_ = _loc3_.getChildAt(1) as GuiLabel;
               }
            }
            if(_loc4_)
            {
               _loc4_.text = landscape.context.locale.translate(LocaleCategory.GUI,param2.label);
               _loc4_.sizeToContent();
               _loc4_.center();
               if(param2.labelOffset)
               {
                  _loc4_.setPosition(_loc4_.x + param2.labelOffset.x,_loc4_.y + param2.labelOffset.y);
               }
            }
         }
      }
      
      private function createSpriteLabel(param1:DisplayObject, param2:LandscapeLayerSpriteDef) : DisplayObject
      {
         var _loc5_:Sprite = null;
         if(!param2.label)
         {
            return param1;
         }
         var _loc3_:GuiLabel = new GuiLabel(landscape.def.labelFontFace,landscape.def.labelFontSize,landscape.def.labelFontColor);
         var _loc4_:DisplayObject = param1;
         if(_loc4_)
         {
            _loc5_ = new Sprite();
            _loc5_.addChild(_loc4_);
            _loc5_.addChild(_loc3_);
            return _loc5_;
         }
         return _loc3_;
      }
      
      private function generateAnimClip(param1:AnimClipResource, param2:LandscapeLayerSpriteDef) : DisplayObject
      {
         if(!param1)
         {
            return null;
         }
         var _loc5_:AnimClipDef = param1.clipDef;
         var _loc4_:AnimClip = new AnimClip(_loc5_,null,null,logger);
         var _loc3_:Number = Math.random() * _loc5_.numFrames;
         _loc4_.repeatLimit = 0;
         _loc4_.start(_loc3_);
         return new AnimClipSprite(_loc4_,param1.movieClipResource,logger,param2.smoothing);
      }
      
      private function generateBitmap(param1:BitmapResource, param2:LandscapeLayerSpriteDef) : DisplayObject
      {
         if(!param1)
         {
            return null;
         }
         var _loc3_:Bitmap = param1.bmp;
         _loc3_.cacheAsBitmap = false;
         if(param2.layer.speed != 0)
         {
            _loc3_.pixelSnapping = "never";
            _loc3_.smoothing = true;
         }
         return _loc3_;
      }
      
      protected function get isWaiting() : Boolean
      {
         var _loc3_:int = 0;
         var _loc2_:Dictionary = waitingResources;
         for(var _loc1_ in _loc2_)
         {
            return true;
         }
         return false;
      }
      
      public function prepareUpdateDelta() : void
      {
         var _loc1_:BoundedCamera = landscape.camera;
         parallax_dx = _loc1_.x;
         parallax_dy = _loc1_.y;
         unclamped_dx = 0;
         unclamped_dy = 0;
         if(_clampParallax && _enableParallax)
         {
            parallax_dx = _loc1_.clampX(parallax_dx);
            parallax_dy = _loc1_.clampY(parallax_dy);
            unclamped_dx = _loc1_.x - parallax_dx;
            unclamped_dy = _loc1_.y - parallax_dy;
         }
      }
      
      public function modifyTransitoryLayer(param1:String, param2:Number, param3:Number) : void
      {
         var _loc4_:LandscapeLayerDef = landscape.def.getLayer(param1);
         if(_loc4_)
         {
            _loc4_.transitory.setTo(param2,param3);
            prepareUpdateDelta();
            updateDeltaLayer(_loc4_);
         }
      }
      
      public function updateDeltaLayer(param1:LandscapeLayerDef) : void
      {
         var _loc2_:Number = _enableParallax ? param1.speed : 1;
         var _loc3_:Sprite = layerDef2LayerSprite[param1];
         _loc3_.x = param1.offset.x + param1.transitory.x - _loc2_ * parallax_dx - unclamped_dx;
         _loc3_.y = param1.offset.y + param1.transitory.y - _loc2_ * parallax_dy - unclamped_dy;
      }
      
      public function updateDelta() : void
      {
         var _loc1_:BoundedCamera = landscape.camera;
         this.scaleX = _loc1_.scale;
         this.scaleY = _loc1_.scale;
         prepareUpdateDelta();
         for each(var _loc2_ in layers)
         {
            updateDeltaLayer(_loc2_);
         }
         landmarks.x = -_loc1_.x;
         landmarks.y = -_loc1_.y;
         if(travelView)
         {
            travelView.x = -_loc1_.x;
            travelView.y = -_loc1_.y;
         }
      }
      
      public function get logger() : ILogger
      {
         return landscape.context.logger;
      }
      
      public function getClickableUnderMouse(param1:Number, param2:Number) : LandscapeLayerSpriteDef
      {
         for each(var _loc3_ in clickables)
         {
            if(_loc3_.isUnderMouse(param1,param2))
            {
               return _loc3_.def;
            }
         }
         return null;
      }
      
      public function get pressedClickable() : LandscapeLayerSpriteDef
      {
         return _pressedClickable;
      }
      
      public function set pressedClickable(param1:LandscapeLayerSpriteDef) : void
      {
         var _loc2_:ClickablePair = null;
         if(_pressedClickable)
         {
            _loc2_ = clickablesByDef[_pressedClickable];
            if(_loc2_)
            {
               _loc2_.clicking = false;
            }
         }
         _pressedClickable = param1;
         if(_pressedClickable)
         {
            _loc2_ = clickablesByDef[_pressedClickable];
            if(_loc2_)
            {
               _loc2_.clicking = true;
            }
         }
      }
      
      public function displayHover(param1:LandscapeLayerSpriteDef) : void
      {
         var _loc2_:ClickablePair = null;
         if(_hoverClickable)
         {
            _loc2_ = clickablesByDef[_hoverClickable];
            if(_loc2_)
            {
               _loc2_.hovering = false;
            }
         }
         _hoverClickable = param1;
         if(_hoverClickable)
         {
            _loc2_ = clickablesByDef[_hoverClickable];
            if(_loc2_)
            {
               _loc2_.hovering = true;
            }
         }
      }
      
      public function get showHelp() : Boolean
      {
         return _showHelp;
      }
      
      public function set showHelp(param1:Boolean) : void
      {
         var _loc2_:LandscapeLayerSpriteDef = null;
         var _loc4_:DisplayObject = null;
         var _loc3_:Sprite = null;
         if(_showHelp != param1)
         {
            _showHelp = param1;
            for(var _loc5_ in helpSpritesByDef)
            {
               _loc2_ = _loc5_ as LandscapeLayerSpriteDef;
               _loc4_ = helpSpritesByDef[_loc2_];
               if(param1 && !_loc4_.parent)
               {
                  _loc3_ = getLayerSprite(_loc2_.layer.nameId);
                  _loc3_.addChild(_loc4_);
               }
               else if(!param1 && _loc4_.parent)
               {
                  _loc4_.parent.removeChild(_loc4_);
               }
            }
         }
      }
      
      private function showClickablesHandler(param1:Event) : void
      {
         for each(var _loc2_ in clickables)
         {
            _loc2_.updateClicking();
         }
      }
      
      public function updateAtmosphere() : void
      {
      }
      
      private function shellCmdFuncLayerList(param1:CmdExec) : void
      {
         var _loc2_:Sprite = null;
         var _loc4_:int = 0;
         for each(var _loc3_ in layers)
         {
            _loc2_ = layerDef2LayerSprite[_loc3_];
            logger.info("Layer " + _loc4_ + " " + _loc3_.nameId + " " + _loc2_.visible);
            _loc4_++;
         }
      }
      
      private function setLayersVisible(param1:String, param2:Boolean) : void
      {
         var _loc3_:LandscapeLayerDef = null;
         if(param1 == "*")
         {
            for each(_loc3_ in layers)
            {
               showLayer(_loc3_,param2);
            }
            return;
         }
         var _loc4_:int = int(param1);
         _loc3_ = landscape.def.layers[_loc4_];
         showLayer(_loc3_,param2);
      }
      
      private function shellCmdFuncLayerHide(param1:CmdExec) : void
      {
         var _loc2_:Array = param1.param;
         if(_loc2_.length > 1)
         {
            setLayersVisible(_loc2_[1],false);
         }
      }
      
      private function shellCmdFuncLayerShow(param1:CmdExec) : void
      {
         var _loc2_:Array = param1.param;
         if(_loc2_.length > 1)
         {
            setLayersVisible(_loc2_[1],true);
         }
      }
      
      private function showLayer(param1:LandscapeLayerDef, param2:Boolean) : void
      {
         if(!param1)
         {
            return;
         }
         var _loc3_:Sprite = layerDef2LayerSprite[param1];
         if(_loc3_)
         {
            _loc3_.visible = param2;
         }
      }
      
      public function setGuidepostEnabled(param1:String, param2:Boolean) : void
      {
         var _loc3_:LandscapeLayerSpriteDef = null;
         var _loc5_:DisplayObject = null;
         var _loc4_:Sprite = null;
         guidepostStates[param1] = param2;
         for(var _loc6_ in guidepostsByDef)
         {
            _loc3_ = _loc6_ as LandscapeLayerSpriteDef;
            if(_loc3_ && _loc3_.guidepost == param1)
            {
               _loc5_ = guidepostsByDef[_loc6_];
               if(_loc5_)
               {
                  if(param2 && !_loc5_.parent)
                  {
                     _loc4_ = getLayerSprite(_loc3_.layer.nameId);
                     _loc4_.addChild(_loc5_);
                  }
                  else if(!param2 && _loc5_.parent)
                  {
                     _loc5_.parent.removeChild(_loc5_);
                  }
               }
            }
         }
      }
      
      public function setClickableEnabled(param1:LandscapeLayerSpriteDef, param2:Boolean) : void
      {
         var _loc3_:ClickablePair = clickablesByDef[param1];
         if(_loc3_)
         {
            _loc3_.enabled = param2;
            if(!param2)
            {
               if(_hoverClickable == _loc3_.def)
               {
                  displayHover(null);
               }
               if(_pressedClickable == _loc3_.def)
               {
                  pressedClickable = null;
               }
            }
         }
      }
      
      public function getClickableDef(param1:String) : LandscapeLayerSpriteDef
      {
         if(!param1)
         {
            return null;
         }
         for each(var _loc2_ in clickables)
         {
            if(_loc2_.def.nameId == param1)
            {
               return _loc2_.def;
            }
         }
         return null;
      }
      
      public function getClickableDisplay(param1:LandscapeLayerSpriteDef) : DisplayObject
      {
         var _loc2_:ClickablePair = clickablesByDef[param1];
         return _loc2_ ? _loc2_.sprite : null;
      }
      
      public function get clampParallax() : Boolean
      {
         return _clampParallax;
      }
      
      public function set clampParallax(param1:Boolean) : void
      {
         if(_clampParallax == param1)
         {
            return;
         }
         _clampParallax = param1;
         updateDelta();
      }
      
      public function get enableParallax() : Boolean
      {
         return _enableParallax;
      }
      
      public function set enableParallax(param1:Boolean) : void
      {
         if(_enableParallax == param1)
         {
            return;
         }
         _enableParallax = param1;
         updateDelta();
      }
      
      public function updateSpriteDefDisplay(param1:LandscapeLayerSpriteDef, param2:Boolean) : void
      {
         var _loc8_:ClickablePair = null;
         var _loc9_:int = 0;
         var _loc6_:int = 0;
         var _loc5_:DisplayObject = spriteDef2Sprite[param1];
         var _loc4_:Boolean = param1 in clickableDefs;
         var _loc7_:Boolean = param1 in helpSpritesByDef;
         var _loc3_:Boolean = param1 in guidepostsByDef;
         var _loc10_:Boolean = _loc5_ is Sprite && (_loc5_ as Sprite).numChildren >= 2 || _loc5_ is GuiLabel;
         param2 ||= param1.clickable != _loc4_;
         param2 ||= param1.help != _loc7_;
         param2 ||= (param1.guidepost ? true : false) != _loc3_;
         param2 ||= (param1.label ? true : false) != _loc10_;
         if(param2 || !_loc5_)
         {
            _loc8_ = clickablesByDef[param1];
            if(_loc8_)
            {
               _loc9_ = clickables.indexOf(_loc8_);
               if(_loc9_ >= 0)
               {
                  clickables.splice(_loc9_,1);
               }
            }
            _loc6_ = clickableDefs.indexOf(param1);
            if(_loc6_ >= 0)
            {
               clickableDefs.splice(_loc6_,1);
            }
            delete spriteDef2Resource[param1];
            delete spriteDef2HoverResource[param1];
            delete clickableDefs[param1];
            delete helpSpritesByDef[param1];
            delete spriteDef2Sprite[param1];
            if(_loc5_)
            {
               if(_loc5_.parent)
               {
                  _loc5_.parent.removeChild(_loc5_);
               }
            }
            addSpriteDef(param1,true);
         }
         else
         {
            updateSpriteDisplay(_loc5_,param1);
         }
      }
      
      public function getDisplayForSpriteDef(param1:LandscapeLayerSpriteDef) : DisplayObject
      {
         return spriteDef2Sprite[param1];
      }
      
      public function get showAnchors() : Boolean
      {
         return _showAnchors;
      }
      
      public function set showAnchors(param1:Boolean) : void
      {
         var _loc6_:Object = null;
         var _loc5_:LandscapeLayerSpriteDef = null;
         var _loc2_:DisplayObject = null;
         var _loc4_:Array = null;
         if(showAnchors == param1)
         {
            return;
         }
         _showAnchors = param1;
         if(!showAnchors)
         {
            _loc4_ = [];
            for(_loc6_ in spriteDef2Sprite)
            {
               _loc5_ = _loc6_ as LandscapeLayerSpriteDef;
               _loc2_ = spriteDef2Sprite[_loc6_];
               if(_loc2_ && _loc2_.parent)
               {
                  _loc2_.parent.removeChild(_loc2_);
                  _loc4_.push(_loc5_);
               }
            }
            for each(_loc5_ in _loc4_)
            {
               delete spriteDef2Sprite[_loc5_];
            }
         }
         else
         {
            for each(var _loc3_ in landscape.def.layers)
            {
               for each(_loc5_ in _loc3_.layerSprites)
               {
                  if(_loc5_.anchor)
                  {
                     _loc2_ = spriteDef2Sprite[_loc6_];
                     if(!_loc2_)
                     {
                        addSpriteDef(_loc5_,true);
                     }
                  }
               }
            }
         }
         dispatchEvent(new Event("LandscapeView.EVENT_SHOW_ANCHORS"));
      }
      
      public function enableSceneElement(param1:Boolean, param2:String, param3:Boolean) : void
      {
         var _loc6_:LandscapeLayerDef = null;
         var _loc4_:ClickablePair = null;
         var _loc5_:DisplayObject = null;
         if(param3)
         {
            _loc6_ = landscape.def.getLayer(param2);
            showLayer(_loc6_,param1);
            return;
         }
         var _loc7_:LandscapeLayerSpriteDef = getSpriteDefFromPath(param2);
         if(_loc7_)
         {
            _loc5_ = spriteDef2Sprite[_loc7_];
            if(_loc5_)
            {
               _loc5_.visible = param1;
            }
            if(_loc7_.clickable)
            {
               _loc4_ = clickablesByDef[_loc7_];
               if(_loc4_)
               {
                  _loc4_.enabled = param1;
               }
            }
         }
      }
   }
}

import engine.landscape.def.LandscapeLayerSpriteDef;
import flash.display.DisplayObject;
import flash.display.DisplayObjectContainer;
import flash.geom.Point;
// JPEXS artifact fix: file-internal classes (after the package block) don't inherit its imports.
// ClickablePair (below) reads the static LandscapeView.showClickables, so it needs this import.
import engine.landscape.view.LandscapeView;

class ClickablePair
{
   
   public var container:DisplayObjectContainer;
   
   public var def:LandscapeLayerSpriteDef;
   
   public var sprite:DisplayObject;
   
   public var hoverSprite:DisplayObject;
   
   private var _enabled:Boolean = true;
   
   private var _hovering:Boolean = false;
   
   private var _clicking:Boolean = false;
   
   public function ClickablePair(param1:LandscapeLayerSpriteDef, param2:DisplayObjectContainer, param3:DisplayObject, param4:DisplayObject)
   {
      this.container = param2;
      this.def = param1;
      this.sprite = param3;
      this.hoverSprite = param4;
      super();
   }
   
   public function get enabled() : Boolean
   {
      return _enabled;
   }
   
   public function set enabled(param1:Boolean) : void
   {
      _enabled = param1;
      if(hoverSprite)
      {
         hoverSprite.visible = enabled;
      }
      if(sprite)
      {
         sprite.visible = enabled;
      }
   }
   
   public function get hovering() : Boolean
   {
      return _hovering;
   }
   
   public function set hovering(param1:Boolean) : void
   {
      if(_hovering == param1)
      {
         return;
      }
      _hovering = param1;
      updateHovering();
   }
   
   public function updateHovering() : void
   {
      if(!hoverSprite)
      {
         return;
      }
      if(!_hovering)
      {
         if(hoverSprite.parent)
         {
            hoverSprite.parent.removeChild(hoverSprite);
         }
      }
      else if(!hoverSprite.parent)
      {
         container.addChild(hoverSprite);
      }
   }
   
   public function get clicking() : Boolean
   {
      return _clicking;
   }
   
   public function set clicking(param1:Boolean) : void
   {
      _clicking = param1;
      updateClicking();
   }
   
   public function updateClicking() : void
   {
      if(!_clicking && !LandscapeView.showClickables)
      {
         if(sprite.parent)
         {
            container.removeChild(sprite);
         }
      }
      else if(!sprite.parent)
      {
         container.addChild(sprite);
      }
   }
   
   public function isUnderMouse(param1:Number, param2:Number) : Boolean
   {
      var _loc3_:Point = null;
      if(enabled)
      {
         if(!sprite.parent)
         {
            _loc3_ = container.globalToLocal(new Point(param1,param2));
            _loc3_.x -= sprite.x;
            _loc3_.y -= sprite.y;
            if(sprite.hitTestPoint(_loc3_.x,_loc3_.y,true))
            {
               return true;
            }
         }
         else if(sprite.hitTestPoint(param1,param2,true))
         {
            return true;
         }
      }
      return false;
   }
}
