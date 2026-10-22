# The OCR plugin references optional language packs. VetDosis instantiates
# only the bundled Latin recognizer; these packs are not shipped in the APK.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
