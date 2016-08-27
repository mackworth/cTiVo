<stylesheet version="1.0" 
xmlns="http://www.w3.org/1999/XSL/Transform">
<output method="text"/>

<template match="originalAirDate|episodeTitle|title|time|movieYear|seriesTitle|isEpisode|seriesId|episodeNumber|displayMajorNumber|callsign|displayMinorNumber|startTime|stopTime|partCount|partIndex|tvRating|mpaaRating">
  <value-of select="name()"/>
  <text> : </text>
  <value-of select="."/>
  <text>
</text>

</template>

<template match="description">
  <value-of select="name()"/>
  <text> : </text>
  <choose>
    <when test="contains(.,' Copyright Rovi, Inc.')">
      <value-of select="substring-before(.,' Copyright Rovi, Inc.')" />
    </when>
    <otherwise>
      <value-of select="." />
    </otherwise>
  </choose>
  <text>
</text>

</template>

<template match="showingBits">
  <value-of select="name()"/>
  <text> : </text>
  <value-of select="@value"/>
  <text>
</text>

</template>
<template match="starRating|colorCode">
  <value-of select="name()"/>
  <text> : </text>
  <value-of select="@value"/>
  <text>
</text>

</template>


<template match="vActor|vGuestStar|vDirector|vExecProducer|vProducer|vWriter|vHost|vChoreographer|vProgramGenre|vSeriesGenre">
  <for-each select="element">
    <if test= "string(.)">
      <for-each select="parent::*">
        <if test="not(@id)">
          <value-of select="name()"/>
        </if>
        <value-of select="./@id"/>
      </for-each>
      <text> : </text>
      <value-of select="."/>
      <text>
</text>
    </if>
  </for-each>
</template>

<template match="vActualShowing">
</template>

<template match="vBookmark">
</template>

<template match="*">
<apply-templates />
</template>

<template match="text()">
</template>

</stylesheet>
