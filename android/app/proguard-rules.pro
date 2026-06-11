# MediaPipe Tasks - AutoValue annotation processor sınıfları
-dontwarn javax.annotation.processing.AbstractProcessor
-dontwarn javax.annotation.processing.SupportedAnnotationTypes
-dontwarn javax.lang.model.SourceVersion
-dontwarn javax.lang.model.element.Element
-dontwarn javax.lang.model.element.ElementKind
-dontwarn javax.lang.model.element.Modifier
-dontwarn javax.lang.model.type.TypeMirror
-dontwarn javax.lang.model.type.TypeVisitor
-dontwarn javax.lang.model.util.SimpleTypeVisitor8

# MediaPipe Tasks - proto ve framework sınıfları
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
