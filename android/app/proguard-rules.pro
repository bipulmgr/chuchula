# Release builds are minified with R8 (Flutter turns it on by default).

# WorkManager (pulled in by the Google Mobile Ads SDK) opens its Room
# database by reflection on the generated WorkDatabase_Impl's no-arg
# constructor. Older Room versions ship a consumer rule that keeps the
# class but not the constructor, so R8 removed it and the app crashed at
# startup with "Failed to create an instance of
# androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
