# löve-zip  
Zero-dependency ZIP file compressor/decompressor module for use with [LÖVE](https://github.com/love2d/love).  
There were a couple existing Lua options but I was yet to find any that could support compressing/decompressing symlinks correctly without either making empty symlink files or duplicating the content, or without wiping the last modified date/time when decompressed by the OS.

> This module is built to work with versions `11.X` and `12.X`

---

## Usage
Simply require the module in your game, some usage examples are shown below. See the API section further down for more details on each method.  
You can also run the `main.lua` file with LÖVE to see some basic examples in action.

As this module uses the LÖVE filesystem, your file paths should be relative to [save directory](https://love2d.org/wiki/love.filesystem.getSaveDirectory) as they are passed directly to `love.filesystem.x`.

```lua
-- load the module
require('love-zip')

-- decompress an existing zip
local unzip = love.zip:newZip()
local decompress, err = unzip:decompress('path/to/my/file.zip', 'path/to/output/')
assert(decompress == true)

-- compress an existing folder to a zip
local zip = love.zip:newZip()
local compress, err = zip:compress('path/to/compress/', 'path/to/output/file.zip')
assert(compress == true)

-- compress while ignoring a list of folders/files
local zip = love.zip:newZip()
local compress, err = zip:compress('path/to/compress/', 'path/to/output/file.zip', {'.DS_Store', 'dist', '.gitignore'})
assert(compress == true)

-- compress specific files/folders manually
local zip = love.zip:newZip()
zip:addFile('path/to/file.txt', 'file.txt') -- single file 
zip:addFolder('file/to/directory') -- specific directory contents
zip:addFolder('file/to/other/directory', {'ignore.txt'}) -- directory contents with ignore list
local compress, err = zip:finish('path/to/final.zip')
assert(compress == true)
```

---

## Notes
The module uses `os.execute()` to mark binary files as executable when decompressing if needed, as well as to resolve and create symlinks, if any.

On Windows, `mklink` is used when decompressing symlinks to recreate the link, this means you will need to run the program as an administrator or you'll see the following error:  
> You do not have sufficient privilege to perform this operation.

---

## API

### love.zip:newZip(verbose_logs)
Creates a new Zip instance to work with.  
| Parameter        | Datatype | Description |
| ---------------- | -------  | ----------- | 
| verbose_logs     | boolean  | output more detailed logs when compressing/decompressing |

Returns a new `Zip` object to use with the methods below

### Zip:decompress(zip_file, output_folder)
Decompresses a given zip file to a given output folder.  
| Parameter        | Datatype | Description |
| ---------------- | -------  | ----------- | 
| zip_file         | string   | relative path of the zip file from the LÖVE $SAVE_DIRECTORY |
| output_folder    | string   | output folder for zip contents |

Returns two values, the first is a `boolean` of whether the method suceeded, the second is an error `string` if an error occured.  

### Zip:compress(target_folder, output_zip, ignore_list)
Compresses an existing folder into a new zip file.  
| Parameter        | Datatype | Description |
| ---------------- | -------  | ----------- | 
| target_folder    | string   | target folder relative to the LÖVE $SAVE_DIRECTORY |
| output_zip       | string   | output path and filename for the zip |
| ignore_list      | table    | list of strings containing files/folders to ignore when zipping |

Returns two values, the first is a `boolean` of whether the method suceeded, the second is an error `string` if an error occured

> If you want more control you can use the following methods to directly add specific files and folders  
> You will need to use `Zip:finish()` when done to commit the added data to disk

### Zip:addFile(target_file, file_path)
Adds a specific file to the zip instance ready to be written.  
| Parameter        | Datatype | Description |
| ---------------- | -------  | ----------- | 
| target_file      | string   | target file to add relative to the LÖVE $SAVE_DIRECTORY |
| file_path        | string   | path of the file to use inside the zip folder |

Returns two values, the first is a `boolean` of whether the method suceeded, the second is an error `string` if an error occured

### Zip:addFolder(target_folder, ignore_list)
Adds the contents of a given folder to the zip instance ready to be written.   
| Parameter        | Datatype | Description |
| ---------------- | -------  | ----------- | 
| target_folder    | string   | target folder relative to the LÖVE $SAVE_DIRECTORY |
| ignore_list      | table    | list of strings containing files/folders to ignore when zipping |

Returns two values, the first is a `boolean` of whether the method suceeded, the second is an error `string` if an error occured

### Zip:finish(output_zip)
Commits all data added via `addFile` and `addFolder` and writes the final zip
| Parameter        | Datatype | Description |
| ---------------- | -------  | ----------- | 
| output_zip       | string   | output path and filename for the zip |

Returns two values, the first is a `boolean` of whether the method suceeded, the second is an error `string` if an error occured
