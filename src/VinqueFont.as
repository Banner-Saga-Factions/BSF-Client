package
{
   import flash.text.Font;

   // JPEXS artifact fix: the decompiler emitted this embedded-font wrapper with an illegal class
   // name (the SWF symbol name contains '$' and '-', invalid in an AS3 identifier), so GameMainAir
   // could not reference it. This is a faithful rename: identical [Embed] metadata, valid class
   // name. The .cff binary lives in src/_assets/ (copied to _decompiled/scripts/_assets/ by
   // apply-patches), which is where the leading-slash source path resolves under -source-path.
   [Embed(source="/_assets/1_vinque_otf$63b1cbd41cd457e212d678672c71ca6a-1365718100.cff",
   fontName="Vinque",
   mimeType="application/x-font",
   fontWeight="normal",
   fontStyle="normal",
   embedAsCFF="true"
   )]
   public class VinqueFont extends Font
   {
      public function VinqueFont()
      {
         super();
      }
   }
}
