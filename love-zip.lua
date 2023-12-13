--[[
  MIT License

  Copyright (c) 2023 ellraiser <ell@tngineers.com>

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
]]

-- @lib  - love-zip
-- @desc - lua zip compressing/decompressing that works cross platform 
--         and can handle symlinks, built for use with LÖVE 11.X+


local bit = require("bit")
love.zip = {


  -- @method - Zip:new()
  -- @desc - creates a new zip instance for compressing/decompressing
  -- @param {boolean} logs - whether to enable verbose logging
  -- @return {userdata} - returns the new zip obj to use
  newZip = function(self, logs)
    local zipcls = {
      files = {},
      path = '',
      error = nil,
      logs = logs,
      offset = 0
    }
    setmetatable(zipcls, self)
    self.__index = self
    return zipcls
  end,


  -- @method - Zip:decompress()
  -- @desc - decompresses a given zip file to a specific output folder
  -- @param {string} path - relative path to zip folder from LÖVE save directory
  -- @param {string} output - output path relative from LÖVE save directory
  -- @return {boolean,string} - returns true,nil if success, else returns false,error
  decompress = function(self, path, output, remapping)

    -- make sure we can read the zip first
    local content, err = love.filesystem.read(path)
    if content == nil then
      print('love.zip > ERROR: ' .. err)
      return nil, err
    end
    self.path = path

    -- make sure output directory exists
    if output == nil then output = '' end
    if output:sub(#output, #output) ~= '/' then
      output = output .. '/'
    end
    love.filesystem.createDirectory(output)
    print('love.zip > decompressing "' .. path .. '" to "' .. output .. '"')

    -- read all content directory entries
    -- these are marked by PK at the start
    -- https://en.wikipedia.org/wiki/ZIP_(file_format)
    local centraldirh = string.find(content, 'PK') or 1
    local centraldir = string.sub(content, centraldirh, #content - 1)
    local entries = {}
    local entry = ''
    -- add data bit by bit until we find a central dir marker 
    -- then add what we found previously
    -- PK is the central footer so thats our 'last' entry done
    for b=1,#centraldir do
      local fbytes = string.sub(centraldir, b, b+3)
      if fbytes == 'PK' and entry ~= '' then
        table.insert(entries, entry)
        entry = ''
      end
      if fbytes == 'PK' then
        table.insert(entries, entry)
        break;
      end
      entry = entry .. string.sub(centraldir, b, b)
    end
    self:_log(#entries .. ' files found')

    -- go through each central dir entry and 
    local files = {}
    for e=1,#entries do

      -- get central dir entry values
      -- https://en.wikipedia.org/wiki/ZIP_(file_format)
      local ebytes = entries[e]
      local compressionformat = love.data.unpack("<i2", string.sub(ebytes, 11, 12))
      local compressedsize = love.data.unpack('<i4', string.sub(ebytes, 21, 24))
      local offset = string.sub(ebytes, 43, 46)
      local filenamesize = love.data.unpack("<i2", string.sub(ebytes, 29, 30))
      local extrasize = love.data.unpack("<i2", string.sub(ebytes, 31, 32))
      local extraattr = string.sub(ebytes, 39, 42)
      local offsetpos = love.data.unpack('<i4', offset)
      local actualname = string.sub(content, offsetpos + 31, offsetpos + 30 + filenamesize)

      -- for each file we have the offset, the length of the file (compressed + 30 + filename)
      -- so we just need to pull that as one string to get our actual data
      local fileoffset = offsetpos + 31 + #actualname + extrasize
      local filedata = string.sub(content, fileoffset, fileoffset + compressedsize - 1)
      local compressed = filedata
      -- if we failed to compress we dont recognise the format 
      if filedata ~= '' and compressionformat == 8 then
        local ok, _ = pcall(love.data.decompress, 'string', 'deflate', filedata)
        if ok == false then
          compressed = filedata
        else
          compressed = love.data.decompress('string', 'deflate', filedata)
        end
      end

      -- remap entries if needed
      if remapping ~= nil then
        for key, value in pairs(remapping) do
          actualname = actualname:gsub(key, value)
        end
      end

      -- for each entry insert the 'file' data we'll need
      table.insert(files, {
        file_name = actualname,
        filename_size = filenamesize,
        extra_attr = extraattr,
        data = compressed
      })

    end

    -- for each file that we found
    for f=1,#files do
      local fdata = files[f]
      local fname = output .. fdata.file_name

      -- directories
      if string.sub(fname, #fname, #fname) == '/' then
        love.filesystem.createDirectory(fname)
        self:_log('writing dir: "' .. fname .. '"')

      -- symlinks store their link as uncompressed data
      -- and their attribute has a special magic value
      -- https://gist.github.com/kgn/610907/dfe4fe04b8499c1cd2ba36b257468c570853ad02
      -- @TODO check just x flagged files to see if there's some other values
      -- as i think this is a+x value 
      elseif love.data.unpack('<I4', fdata.extra_attr) == 2716663808 then
        
        -- handle symlinks AFTER making all files or might get issues on windows
        
      else
 
        -- zips made on windows won't always have the 'empty' directory entries like unix
        -- because of that when making files we'll need to make the directories that we need
        local filedir = fname:sub(1, fname:find("/[^/]*$"))
        love.filesystem.createDirectory(filedir)

        -- otherwise standard file just make a file
        local suc, err = love.filesystem.write(fname, fdata.data)
        self:_log('writing itm: "' .. fname .. '"')

        -- if flagged as an executable then we need to chmod it on unix platforms
        if love.data.unpack('<I4', fdata.extra_attr) == 2179792896 and love.system.getOS() ~= 'Windows' then
          os.execute('chmod +x "' .. love.filesystem.getSaveDirectory() .. '/' .. fname .. '"')
        end
        if suc ~= true then
          print('love.zip > ERROR: failed to write file: "' .. err .. '"')
        end

      end
    end

    -- process symlinks after if any
    -- sort in order so that we dont try and create symlinks of symlinks if nested
    table.sort(files, function(fa, fb)
      if #fa.data > #fb.data then return false end
      if #fa.data < #fb.data then return true end
      return false
    end)
    for f=1,#files do
      local fdata = files[f]
      local fname = output .. fdata.file_name
      
      if love.data.unpack('<I4', fdata.extra_attr) == 2716663808 then
        
        -- get relative full path for os.execute
        local fullpath = love.filesystem.getSaveDirectory() .. '/'
        local lastslash = string.find(fname, "/[^/]*$")
        local lname = fname:sub(1, lastslash)
        
        -- create symlink based on symlink entry data 
        -- this is a relative path from the path of the file
        -- windows needs mklink instead of ln, which requires admin permissions
        local linker = 'ln -s -f "' .. fullpath .. lname .. fdata.data .. '" "' .. fullpath .. fname .. '"'
        if love.system.getOS() == 'Windows' then
          -- we also have to work out if out symlink is for a directory OR a file
          -- as mklink needs a flag for directories
          local info = love.filesystem.getInfo(lname .. fdata.data)
          local flag = ''
          if info.type == 'directory' then
            flag = '/D'
          end
          linker = 'mklink ' .. flag .. ' "' .. fullpath .. fname .. '" "' .. fullpath .. lname .. fdata.data .. '"'
        end
        os.execute(linker)
        self:_log('writing sym: "' .. lname .. fdata.data .. '"')
      end

    end

    self:_log('finished writing')
    print('love.zip > finished decompression')

    return true, nil

  end,


  -- @method - Zip:compress()
  -- @desc - compress a given folder to a specific output zip
  -- @param {string} path - relative path to target folder from LÖVE save directory
  -- @param {string} output - output zip path relative from LÖVE save directory
  -- @param {table} ignore - optional list of file/folders to ignore
  -- @return {boolean,string} - returns true,nil if success, else returns false,error
  compress = function(self, path, output, ignore)
    print('love.zip > compressing directory: "' .. path .. '"')
    if ignore == nil then ignore = {} end
    if output == nil then output = '' end
    self.path = output
    self:addFolder(path, ignore)
    self:_log('writing files to: "' .. output .. '"')
    return self:finish()
  end,


  -- @method - Zip:addFile()
  -- @desc - adds a given file to the zip instance, this just adds the data in
  --         memory, Zip:finish() must be called to commit to the file
  -- @param {string} filename - path to file relative to LÖVE save directory
  -- @return {boolean,string} - returns true,nil if success, else returns false,error
  addFile = function(self, filename, path)
    local content, err = love.filesystem.read(filename)
    if content == nil then return nil, err end
    print('love.zip > adding itm: "' .. filename .. '"')
    return self:_add(path or filename, content)
  end,


  -- @method - Zip:addFolder()
  -- @desc - adds a given folder and all the items in it to the zip instance,
  --         this just adds the data, Zip:finish() must be called to commit to file
  -- @param {string} dir - path to folder relative to LÖVE save directory
  -- @param {string} ignore - list of files/folders to ignore when adding
  -- @param {string} _folder - used internally when recursively adding items
  -- @param {string} _opath - used internally for symlinks to keep original path
  -- @return {boolean,string} - returns true,nil if success, else returns false,error
  addFolder = function(self, dir, ignore, _folder, _opath)
    if ignore == nil then ignore = {} end
    if _folder == nil then _folder = '' end
    if _opath == nil then 
      print('love.zip > adding dir: "' .. dir .. '"')
      _opath = dir
    end
    local files = love.filesystem.getDirectoryItems(dir)
    for f=1,#files do
      local item = files[f]
      local ignored = false
      for i=1,#ignore do
        if ignore[i] == item then
          ignored = true
        end
      end
      if ignored == false then
        local info = love.filesystem.getInfo(dir .. '/' .. files[f])
        if info ~= nil then

          -- for normal files just write them
          -- pass in executable attribute if we think it might be executable 
          if info.type == 'file' then
            local content, _ = love.filesystem.read(dir .. '/' .. files[f])
            local execv = nil
            -- not an exact science but here we are
            if files[f]:find('%.') == nil then
              execv = 2179792896
            end
            -- work out timestamp
            self:_log('adding itm: "' .. _folder .. files[f] .. '"')
            self:_add(_folder .. files[f], content, execv, info.modtime)

          -- for directories add a directory entry 
          -- then add the directory itself
          elseif info.type == 'directory' then
            self:_log('adding dir: "' .. _folder .. files[f] .. '/"')
            self:_add(_folder .. files[f] .. '/', '')
            self:addFolder(dir .. '/' .. files[f], ignore, _folder .. files[f] .. '/', _opath)

          -- for symlinks we need to resolve the path ourselves as love cant give us this
          -- then we can write the symlink file which is just an uncompressed relative path
          -- with a special attribute to flag it as a symlink on unix 
          elseif info.type == 'symlink' then
            local path = self:_resolveSymlink(love.filesystem.getSaveDirectory() .. '/' .. dir .. '/' .. files[f])
            local start_path = _folder .. files[f]
            local relative_path = path:gsub(love.filesystem.getSaveDirectory(), '')
            local regex_path = '/' .. _opath .. '/'
            regex_path = regex_path:gsub('%-', '%%-')
            regex_path = regex_path:gsub('%.', '%%.')
            local sym_path = relative_path:gsub(regex_path, '')
            if start_path:find("/[^/]*$") ~= nil then
              local relative_folder = start_path:sub(1, start_path:find("/[^/]*$") - 1) .. '/'
              relative_folder = relative_folder:gsub('%-', '%%-')
              relative_folder = relative_folder:gsub('%.', '%%.')
              sym_path = sym_path:gsub(relative_folder, '')
            end
            if sym_path:find('\n') then
              sym_path = sym_path:gsub('\n', '')
            end
            self:_log('adding sym: "' .. start_path .. '" > "' .. sym_path .. '"')
            self:_add(start_path, sym_path, 2716663808)
          end
        end
      end
    end
    return true, nil
  end,


  -- @method - Zip:finish()
  -- @desc - commits all added files and folders to the file
  -- @param {string} path - used when calling manually to set the output zip file 
  --                        path to use, relative to the LÖVE save directory
  -- @return {boolean,string} - returns true,nil if success, else returns false,error
  finish = function(self, _path)

    if self.path == '' then self.path = _path end

    -- add file headers first
    local zipdata = ''
    for f=1,#self.files do
      zipdata = zipdata .. self.files[f].zipdata
    end

    -- add central directory entries for each file
    -- https://en.wikipedia.org/wiki/ZIP_(file_format)
    local centraldir = ''
    for f=1,#self.files do
      local file = self.files[f]
      local extra_attr = '    '
      local comp = file.compression_type
      if file.extra ~= '' then
        extra_attr = love.data.pack('string', '<I4', file.extra)
      end
      centraldir = centraldir .. 'PK'                              -- header signature, 4 bytes, 0x02014b50 
      centraldir = centraldir .. ''                                -- version made by, 4 bytes, just used unix
      centraldir = centraldir .. ' '                                -- version needed, 4 bytes, 20 > 2.0
      centraldir = centraldir .. '  '                                -- flags, 2 bytes, empty
      centraldir = centraldir .. self:_intToBytes(comp, 2)            -- compression, 2 bytes, 8
      centraldir = centraldir .. file.lastmodtime                     -- last mod time, 2 bytes, empty
      centraldir = centraldir .. file.lastmoddate                     -- last mode date, 2 bytes, empty
      centraldir = centraldir .. self:_intToBytes(file.crc,4)          -- crc32 of uncompressed data, 4 bytes
      centraldir = centraldir .. self:_intToBytes(#file.compressed,4)  -- compressed size - 4 bytes
      centraldir = centraldir .. self:_intToBytes(#file.content,4)     -- uncompressed size - 4 bytes
      centraldir = centraldir .. self:_intToBytes(#file.filename,2)    -- file name length - 2 bytes
      centraldir = centraldir .. '  '                                -- extra field length - 2 bytes, empty
      centraldir = centraldir .. '  '                                -- file comment length - 2 bytes, empty
      centraldir = centraldir .. '  '                                -- disk number - 2 bytes, empty / 0
      centraldir = centraldir .. '  '                                -- internal attributes - 2 bytes, empty
      centraldir = centraldir .. extra_attr                           -- external attributes, 4 bytes, empty
      centraldir = centraldir .. self:_intToBytes(file.offset, 4)     -- offset of local header, 4 bytes
      centraldir = centraldir .. file.filename                        -- file name (variable size)
    end

    -- add central directory footer
    local endcentral = ''
    endcentral = endcentral .. 'PK'
    endcentral = endcentral .. '  '                           -- number of this disk - 2 bytes, empty / 0
    endcentral = endcentral .. '  '                           -- number of the disk with the start of the central directory, 2 bytes, empty / 0
    endcentral = endcentral .. self:_intToBytes(#self.files,2)  -- total number of entries on this disk, 2 bytes, empty / 0
    endcentral = endcentral .. self:_intToBytes(#self.files,2)  -- total number of entries in the central directory, 2 bytes
    endcentral = endcentral .. self:_intToBytes(#centraldir,4)  -- size of the central directory, 4 bytes
    endcentral = endcentral .. self:_intToBytes(#zipdata,4)     -- offset of start of central directory, 4 bytes
    endcentral = endcentral .. '  '                           -- zip file comment length, 2 bytes

    -- write full zip data to file
    local suc, err = love.filesystem.write(self.path, zipdata .. centraldir .. endcentral)
    if suc == true then
      print('love.zip > finished compression')
      return true, nil
    else
      print('love.zip > ERROR: failed to write final zip: "' .. err .. '"')
      return nil, err
    end

  end,


  -- @method - Zip:_add()
  -- @desc - internal method to add a file's contents to the zip instance
  -- @param {string} filename - name of the file being added
  -- @param {string} content - content of the file to add
  -- @param {number} extraattr - extra attribute to set for file entry, this is 
  --                             used to set symlinks + executable files
  -- @return {boolean,string} - returns true,nil if success, else returns false,error
  _add = function(self, filename, content, extraattr, modtime)

    local fileCRC32 = self:_crc32(content)
    local compressed = love.data.compress('string', 'deflate', content, 9)
    local compression_type = 8

    -- symlinks dont get compressed, the symlink path is the raw data inside
    -- so need to set the raw data and change compression method in the header
    if extraattr == 2716663808 then
      compressed = content .. ''
      compression_type = 0
    end

    -- calculate modtime, either use what we can read from getInfo()
    -- or just default to today for directory/symlinks that dont have a modtime
    local dtable = os.date("*t", modtime)
    local dostime = self:_msdosWrite(dtable.sec, dtable.min, dtable.hour, 'time')
    local dosdate = self:_msdosWrite(dtable.day, dtable.month, dtable.year, 'date')
    local lastmodtime = self:_intToBytes(dostime, 2)
    local lastmoddate = self:_intToBytes(dosdate, 2)

    -- file header
    -- https://en.wikipedia.org/wiki/ZIP_(file_format)
    local zipdata = ''
    zipdata = zipdata .. 'PK'                               -- header signature, 4 bytes, 0x04034b50
    zipdata = zipdata .. ' '                                 -- zip version needed to extract, 2 bytes, 20 (2.0)
    zipdata = zipdata .. '  '                                 -- General purpose bit flag, 2 bytes, dont need
    zipdata = zipdata .. self:_intToBytes(compression_type,2)  -- Compression method, 2 bytes, 8 (deflated)
    zipdata = zipdata .. lastmodtime                           -- last mod time, 2 bytes
    zipdata = zipdata .. lastmoddate                           -- last mode date, 2 bytes
    zipdata = zipdata .. self:_intToBytes(fileCRC32,4)         -- crc32 of uncompressed data, 4 bytes
    zipdata = zipdata .. self:_intToBytes(#compressed,4)       -- compressed size, 4 bytes
    zipdata = zipdata .. self:_intToBytes(#content,4)          -- uncompressed size, 4 bytes
    zipdata = zipdata .. self:_intToBytes(#filename,2)         -- file name length, 2 bytes
    zipdata = zipdata .. '  '                                 -- extra field length, 2 bytes, dont need
    zipdata = zipdata .. filename                              -- file name (variable size)

    -- file data
    zipdata = zipdata .. compressed

    -- data descriptor
    zipdata = zipdata .. 'PK'                          -- header signature, 4 bytes, 0x08074b50
    zipdata = zipdata .. self:_intToBytes(fileCRC32,4)    -- crc32 of uncompressed data, 4 bytes
    zipdata = zipdata .. self:_intToBytes(#compressed,4)  -- compressed size, 4 bytes
    zipdata = zipdata .. self:_intToBytes(#content,4)     -- uncompressed size, 4 bytes

    -- add to files list
    table.insert(self.files, {
      offset = self.offset + 0,
      zipdata = zipdata,
      filename = filename,
      content = content,
      extra = extraattr or '',
      compressed = compressed,
      compression_type = compression_type,
      lastmodtime = lastmodtime,
      lastmoddate = lastmoddate,
      crc = fileCRC32
    })

    -- update offset for next file added
    self.offset = self.offset + #zipdata
    return true, nil

  end,


  -- @method - Zip:_add()
  -- @desc - internal method to print output when logs are enabled
  -- @param {string} msg - message to print
  -- @return {nil}
  _log = function(self, msg)
    if self.logs == true then print('love.zip > ' .. msg) end
  end,


    --[[
    https://users.cs.jmu.edu/buchhofp/forensics/formats/pkzip.html
    https://learn.microsoft.com/en-gb/windows/win32/api/winbase/nf-winbase-dosdatetimetofiletime
      File modification time 	stored in standard MS-DOS format:
        Bits 00-04: seconds divided by 2 (5)
        Bits 05-10: minute (6)
        Bits 11-15: hour (5)
      File modification date 	stored in standard MS-DOS format:
        Bits 00-04: day (5)
        Bits 05-08: month (4)
        Bits 09-15: years from 1980 (7)
    ]]--
  _msdosWrite = function(self, a, b, c, type)
    --> day, month, year
    if type == 'date' then
      local dosdate = 0x00000000;
      dosdate = bit.bxor(dosdate, bit.lshift(a, 0));         -- 00-04
      dosdate = bit.bxor(dosdate, bit.lshift(b, 5));         -- 05-08
      dosdate = bit.bxor(dosdate, bit.lshift((c-1980), 9));  -- 09-15
      return dosdate
    --> hours, mins, secs
    else 
      local dostime = 0x00000000;
      dostime = bit.bxor(dostime, bit.lshift(c/2, 0));       -- 00-04
      dostime = bit.bxor(dostime, bit.lshift(b, 5));         -- 05-10
      dostime = bit.bxor(dostime, bit.lshift(a, 11));        -- 11-15
      return dostime
    end
  end,


  -- @method - Zip:_intToBytes()
  -- @desc - internal method to convert a given int to a set number of bytes
  -- @param {number} int - integer to convert
  -- @param {number} size - number of bytes
  -- @return {string} - returns converted bytes
  -- @TODO change to use love.data.pack?
  _intToBytes = function(self, int, size)
    local t = {}
    for i=1,size do
      t[i] = string.char(bit.band(int, 255)) -- t[i] = int & 0xFF
      int = bit.rshift(int, 8) -- int = int >> 8
    end
    return table.concat(t)
  end,


  -- @method - Zip:_resolveSymlink()
  -- @desc - internal method to get the full path of a symlink using terminal
  --         currently LÖVE (which is using physfs) doesnt return the actual
  --         resolved symlink path 
  -- @param {string} path - full path of symlink to resolve
  -- @return {string} - returns resolved path
  _resolveSymlink = function(self, path)
    local cmd = 'readlink "' .. path .. '"'
    local dir = path:sub(1, path:find("/[^/]*$") - 1)
    -- on windows we need to run dir on the containing directory
    -- as otherwise running dir directly on a symlink dir will just dir the symlink target
    if love.system.getOS() == 'Windows' then
      cmd = 'dir "' .. string.gsub(dir, '/', '\\') .. '"'
    end
    local handle = io.popen(cmd)
    if handle == nil then return '' end
    local result = handle:read("*a")
    handle:close()
    if love.system.getOS() == 'Windows' then
      path = string.gsub(path, '\\', '/')
      dir = string.gsub(dir, '\\', '/')
      result = string.gsub(result, '\\', '/')
      local syminfo = path:sub(path:find("/[^/]*$"), #path)
      syminfo = ' ' .. syminfo:sub(2, #syminfo) .. ' %['
      syminfo = syminfo:gsub('%-', '%%-')
      local target = result:sub(result:find(syminfo) + #syminfo - 1, #result)
      target = target:sub(1, target:find('%]') - 1)
      return string.gsub(target, '\\', '/')
    end
    return result
  end,


  -- @method - Zip:_crc32()
  -- @desc - calculates the crc32 hash for a given file's data
  -- @param {string} data - data to hash
  -- @return {string} - returns the hash
  -- @NOTE ported from C example here:
  -- https://en.wikipedia.org/wiki/Computation_of_cyclic_redundancy_checks#CRC-32_algorithm
  -- bit slow but guess can't help that given what it's doing?
  _crc32 = function(self, data)
    -- cache modules http://bitop.luajit.org/api.html
    local band, bxor, rshift = bit.band, bit.bxor, bit.rshift
    local crc32 = 0xFFFFFFFF
    local data_len = #data
    for d=1,data_len do
      local byte = string.byte(data:sub(d, d))
      local lookup = band(bxor(crc32, byte), 0xFF)
      crc32 = bxor(rshift(crc32, 8), self._crctable[lookup+1])
    end
    crc32 = bxor(crc32, 0xFFFFFFFF)
    return crc32
  end,


  --[[
    COPYRIGHT (C) 1986 Gary S. Brown.  You may use this program, or
    code or tables extracted from it, as desired without restriction.
    https://opensource.apple.com/source/xnu/xnu-1456.1.26/bsd/libkern/crc32.c
  ]]--
  -- @property - Zip:_crctable
  -- @desc - used to calculate the zip files crc32 attribute for each file
  --         see method below
  _crctable = {
    0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f,
    0xe963a535, 0x9e6495a3,	0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988,
    0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91, 0x1db71064, 0x6ab020f2,
    0xf3b97148, 0x84be41de,	0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
    0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec,	0x14015c4f, 0x63066cd9,
    0xfa0f3d63, 0x8d080df5,	0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172,
    0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b,	0x35b5a8fa, 0x42b2986c,
    0xdbbbc9d6, 0xacbcf940,	0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
    0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423,
    0xcfba9599, 0xb8bda50f, 0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924,
    0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d,	0x76dc4190, 0x01db7106,
    0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
    0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d,
    0x91646c97, 0xe6635c01, 0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e,
    0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457, 0x65b0d9c6, 0x12b7e950,
    0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
    0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2, 0x4adfa541, 0x3dd895d7,
    0xa4d1c46d, 0xd3d6f4fb, 0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0,
    0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9, 0x5005713c, 0x270241aa,
    0xbe0b1010, 0xc90c2086, 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
    0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81,
    0xb7bd5c3b, 0xc0ba6cad, 0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a,
    0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683, 0xe3630b12, 0x94643b84,
    0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
    0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb,
    0x196c3671, 0x6e6b06e7, 0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc,
    0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5, 0xd6d6a3e8, 0xa1d1937e,
    0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
    0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60, 0xdf60efc3, 0xa867df55,
    0x316e8eef, 0x4669be79, 0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236,
    0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f, 0xc5ba3bbe, 0xb2bd0b28,
    0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
    0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f,
    0x72076785, 0x05005713, 0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38,
    0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21, 0x86d3d2d4, 0xf1d4e242,
    0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
    0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69,
    0x616bffd3, 0x166ccf45, 0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2,
    0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db, 0xaed16a4a, 0xd9d65adc,
    0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
    0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6, 0xbad03605, 0xcdd70693,
    0x54de5729, 0x23d967bf, 0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94,
    0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d
  }


}
