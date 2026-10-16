package com.goldenfalcons.sailinggps
import org.junit.Assert.assertEquals
import org.junit.Test

class DefaultWaypointFolderTest {
    @Test fun selectedEmptyFolderIsUsedForNewCurrentPosition() {
        assertEquals("B",DefaultWaypointFolder.resolve("B",listOf("A","B"),listOf("A")))
    }
    @Test fun unsetOrDeletedDefaultDoesNotDependOnPointInsertionOrder() {
        for(saved in listOf(null,"","deleted")) {
            assertEquals("A",DefaultWaypointFolder.resolve(saved,emptyList(),listOf("Z","A")))
            assertEquals("A",DefaultWaypointFolder.resolve(saved,emptyList(),listOf("A","Z")))
        }
    }
    @Test fun emptyLibraryUsesAnExistingFolderBeforeCreatingFallback() {
        assertEquals("A",DefaultWaypointFolder.resolve(null,listOf("B","A"),emptyList()))
        assertEquals("メインフォルダ",DefaultWaypointFolder.resolve(null,emptyList(),emptyList()))
    }
}
