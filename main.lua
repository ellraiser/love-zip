-- example usage in a LÖVE project

-- require the module
require('love-zip')

love.load = function()

  -- make a directory in $SAVE_DIRECTORY for output
  love.filesystem.createDirectory('lovezip')

  -- compress the contents of 'examples/saves'
  -- to '$SAVE_DIRECTORY/lovezip/savefiles.zip'
  local zip = love.zip:newZip()
  local compress, _err = zip:compress('examples/saves', 'lovezip/savefiles.zip')
  assert(compress == true)

  -- decompress the contents of 'examples/mods/nei.zip'
  -- to '$SAVE_DIRECTORY/lovezip/mods/'
  local unzip = love.zip:newZip()
  local decompress, _err = unzip:decompress('examples/mods/nei.zip', 'lovezip/mods')
  assert(decompress == true)

  -- compress specific files 
  -- to '$SAVE_DIRECTORY/lovezip/specific.zip'
  local szip = love.zip:newZip()
  szip:addFile('examples/saves/save1.sav', 'subdir/save1.sav')
  szip:addFolder('examples/plugins/plugin_a')
  local compress, _err = szip:finish('lovezip/specific.zip')
  assert(compress == true)

  -- open the $SAVE_DIRECTORY to view output
  love.system.openURL('file://' .. love.filesystem.getSaveDirectory() .. '/lovezip')

  -- quit the 'game'
  love.event.quit(1)

end
