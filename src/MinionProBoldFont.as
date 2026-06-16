package
{
   import flash.text.Font;

   // JPEXS artifact fix: faithful rename of the decompiler's illegal-named embedded-font wrapper
   // (SWF symbol name has '$' and '-'). Identical [Embed] metadata, valid class name. See VinqueFont.as.
   [Embed(source="/_assets/3_MinionPro-Bold_otf$99c3f20af978dc8191f4e15bbdccf56c-32419151.cff",
   fontName="Minion Pro",
   mimeType="application/x-font",
   fontWeight="bold",
   fontStyle="normal",
   embedAsCFF="true"
   )]
   public class MinionProBoldFont extends Font
   {
      public function MinionProBoldFont()
      {
         super();
      }
   }
}
