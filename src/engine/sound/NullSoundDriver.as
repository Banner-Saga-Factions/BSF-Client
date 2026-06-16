package engine.sound
{
   import engine.core.logging.ILogger;
   import engine.sound.config.ISoundSystem;
   import engine.sound.def.ISoundDef;
   import flash.events.EventDispatcher;
   import flash.utils.Dictionary;
   
   public class NullSoundDriver extends EventDispatcher implements ISoundDriver
   {
      
      private var _preloader:IFevPreloader = new NullFevPreloader();
      
      private var _config:ISoundSystem;
      
      public function NullSoundDriver(param1:ISoundSystem, param2:ILogger)
      {
         super();
         this._config = param1;
         param2.info("NullSoundDriver created");
      }
      
      public function get system() : ISoundSystem
      {
         return _config;
      }
      
      public function setParameter() : void
      {
      }
      
      public function getGroup(param1:String) : void
      {
      }
      
      public function playEvent(param1:String) : Number
      {
         return 0;
      }
      
      public function stopEvent(param1:Number, param2:Boolean) : void
      {
      }
      
      public function isLooping(param1:Number) : Boolean
      {
         return false;
      }
      
      public function isPlaying(param1:Number) : Boolean
      {
         return false;
      }
      
      public function dispose() : void
      {
      }
      
      public function preloadSoundDefData(param1:Vector.<ISoundDef>) : ISoundDefBundle
      {
         return new NullSoundDefBundle();
      }
      
      public function get disposed() : Boolean
      {
         return false;
      }
      
      public function get fevPreloader() : IFevPreloader
      {
         return _preloader;
      }
      
      public function init(param1:Boolean) : Boolean
      {
         return true;
      }
      
      public function reverbAmbientPreset(param1:String) : Boolean
      {
         return false;
      }
      
      public function setEventParameter(param1:String, param2:String, param3:Number) : Boolean
      {
         return false;
      }
      
      public function getEventParameter(param1:String, param2:String) : Number
      {
         return 0;
      }
      
      public function systemUpdate() : Boolean
      {
         return true;
      }
      
      public function netEventSystem_Init(param1:int) : Boolean
      {
         return true;
      }
      
      public function netEventSystem_Update() : Boolean
      {
         return true;
      }
      
      public function netEventSystem_Shutdown() : Boolean
      {
         return true;
      }
      
      public function get playing() : Dictionary
      {
         return null;
      }
      
      public function getParams(param1:String) : Dictionary
      {
         return null;
      }
      
      public function get reverb() : String
      {
         return null;
      }
      
      public function checkPlaying() : void
      {
      }
      
      public function getNumEventParameters(param1:Number) : int
      {
         return 0;
      }
      
      public function getEventParameterName(param1:Number, param2:int) : String
      {
         return null;
      }
      
      public function getEventParameterValue(param1:Number, param2:int) : Number
      {
         return 0;
      }
      
      public function getEventParameterValueByName(param1:Number, param2:String) : Number
      {
         return 0;
      }
      
      public function getEventParameterVelocity(param1:Number, param2:int) : Number
      {
         return 0;
      }
      
      public function getEventParameterSeekSpeed(param1:Number, param2:int) : Number
      {
         return 0;
      }
   }
}

// JPEXS decompile artifact fix: file-internal classes (declared after the package block) do NOT
// inherit the package block's imports, so this top-level import is required for NullFevPreloader to
// resolve IFevPreloader (engine.sound). JPEXS emits these post-package imports for most such files
// but dropped this one. Unrelated to any feature -- needed for the decompile to compile at all.
import engine.sound.IFevPreloader;

class NullFevPreloader implements IFevPreloader
{
   
   public function NullFevPreloader()
   {
      super();
   }
   
   public function addFev(param1:String) : void
   {
   }
   
   public function load(param1:Function) : void
   {
      param1(this);
   }
   
   public function get complete() : Boolean
   {
      return true;
   }
}
