package
{
   import flash.text.Font;

   // JPEXS artifact fix: faithful rename of the decompiler's illegal-named embedded-font wrapper
   // (SWF symbol name has '$' and '-'). Identical [Embed] metadata, valid class name. See VinqueFont.as.
   [Embed(source="/_assets/2_MinionPro-Regular_otf$33ff4a51504a3ddbd8f9d36f3a153cb71829105478.cff",
   fontName="Minion Pro",
   mimeType="application/x-font",
   fontWeight="normal",
   fontStyle="normal",
   embedAsCFF="true"
   )]
   public class MinionProRegularFont extends Font
   {
      public function MinionProRegularFont()
      {
         super();
      }
   }
}
