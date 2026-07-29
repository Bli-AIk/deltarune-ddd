return {
  version = "1.10",
  luaversion = "5.1",
  tiledversion = "1.12.2",
  name = "platform",
  class = "",
  tilewidth = 320,
  tileheight = 222,
  spacing = 0,
  margin = 0,
  columns = 0,
  objectalignment = "unspecified",
  tilerendersize = "tile",
  fillmode = "stretch",
  tileoffset = {
    x = 0,
    y = 0
  },
  grid = {
    orientation = "orthogonal",
    width = 1,
    height = 1
  },
  properties = {},
  wangsets = {},
  tilecount = 5,
  tiles = {
    {
      id = 0,
      image = "../../../assets/sprites/tilesets/room_cc_kingbattle/platform.png",
      width = 320,
      height = 222
    },
    {
      id = 1,
      image = "../../../assets/sprites/tilesets/room_cc_kingbattle/003.png",
      width = 175,
      height = 45,
      animation = {
        {
          tileid = 4,
          duration = 300
        },
        {
          tileid = 3,
          duration = 300
        },
        {
          tileid = 2,
          duration = 300
        },
        {
          tileid = 1,
          duration = 300
        }
      }
    },
    {
      id = 2,
      image = "../../../assets/sprites/tilesets/room_cc_kingbattle/002.png",
      width = 175,
      height = 45
    },
    {
      id = 3,
      image = "../../../assets/sprites/tilesets/room_cc_kingbattle/001.png",
      width = 175,
      height = 45
    },
    {
      id = 4,
      image = "../../../assets/sprites/tilesets/room_cc_kingbattle/000.png",
      width = 175,
      height = 45
    }
  }
}
