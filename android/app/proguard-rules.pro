# Rules for R8, which shrinks the release build.

# Google Mobile Ads uses WorkManager, whose Room database classes are
# created by reflection. R8 removed WorkManager's generated database, so the
# app crashed at start ("Failed to create an instance of
# androidx.work.impl.WorkDatabase"). Keep Room databases and WorkManager.
-keep class * extends androidx.room.RoomDatabase { <init>(...); }
-keep class **_Impl { <init>(...); }
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
