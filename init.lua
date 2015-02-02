local M = {}
local io = require 'io'
local os = require 'os'
local lfs = require 'lfs'

-- Default config
M.projects = {
	-- each key represents a project... KeyName is project name
  TextAdeptConf = {
    build = {},
    types = {},
    exclude = {"/.git","/.hg","/docs"},
    folders = {
      "~/.textadept"
    }
  }
}

M.defaultTagCmd = "ctags --sort=yes  --fields=+KS-sf --excmd=number -f - "

M.HOMEDIR = "/"
local pathSep = "/"
if WIN32 then
  M.HOMEDIR = os.getenv('USERPROFILE')..'\\'
  pathSep = '\\'
else
  M.HOMEDIR = os.getenv('HOME')
end

M.debug = false

local function dprint(msg)
	if M.debug == true then
		print(os.date("%H:%M:%S ").." [Project]: "..msg)
	end
end

local function translateFolder(v)
        return string.gsub(v, "^~", M.HOMEDIR)
end

function M.findProjectRoot()
  for k, v in pairs(M.projects) do
    if v["folders"] then
      for i,f in ipairs(v.folders) do
				f = translateFolder(f)
        if buffer.filename:match('('..f..'[/\\][^/\\]+)[/\\].+') then
          return f
        end

      end
    end
  end

  local root = io.get_project_root(buffer.filename)

  if root then
    return root
  end

  return buffer.filename:match('(.+)[/\\]')
end

function M.selectProject()
  local projectList = {}
  for k, v in pairs(M.projects) do
    projectList[#projectList + 1] = k
  end

  if projectList and #projectList > 0 then
    local button, i = ui.dialogs.filteredlist{
      title = 'Goto Project',
      columns = {'Name'},
      items = projectList,
      width = 600
    }

    if button == 1 then
        for k, v in pairs(M.projects) do
          if k == projectList[i] then
	    v.name = k
            M.project_showfiles(v)
            break
          end
        end
    end
  end
end

local function dir_foreach(dir, f, filter, level)
	if not level then level = 0 end
	if level == 0 then
		local cnt = 0
		filter.extMap = {}
		for i = 1, #filter.types do
			local ext = filter.types[i]
			filter.extMap[ext] = true
			cnt = cnt + 1
		end
		filter.extMapCnt = cnt
	end

	for file in lfs.dir(dir) do
		if not file:find('^%.%.?$') then -- ignore . and ..
			local fullfile = dir..pathSep..file
			local type = lfs.attributes(fullfile, 'mode')
			if type == 'directory' then
				local e = false
				for i = 1, #filter.exclude do
					if string.find(fullfile, filter.exclude[i])  then
						e = true
						break
					end
				end

				if e == false then
					dir_foreach(fullfile, f, filter, level + 1)
				end
			elseif type == 'file' then
				if filter.extMapCnt == 0 or filter.extMap[file:match('[^%.]+$')] == true then
					if f(fullfile, dir, file) == false then return end
				end
			end
		end
	end
end

function M.project_findFiles(projectDef)
  if projectDef.cache then
      return { files = projectDef.cache.files, fpaths = projectDef.cache.fpaths }
  end

  local files = {}
  local fpaths = {}

  for i,f in ipairs(projectDef.folders) do
	f = translateFolder(f)
	dir_foreach(f, (function(name, dir, file)
		if name then
			--[[ local fidx = string.find(string.reverse(name), pathSep)
			 local fname

			  if (fidx == nil) then
			    fname = "Unknown"
			  else
			    fname = string.sub(name, string.len(name) - fidx + 2)
			  end
			]]--
			  fpaths[#fpaths + 1] = name

			  --name = string.sub(name, 1, string.len(name) - fidx)
			  name = string.gsub(name, M.HOMEDIR, "~")

			 -- files[#files + 1] = fname
			  files[#files + 1] = name
		end
	end), projectDef, nil)
  end

  projectDef.cache = {
    files = files,
    fpaths = fpaths
  }
  return { files = files, fpaths = fpaths }
end

function M.project_showfiles(p)

  local returnPaths = M.project_findFiles(p)
  local files = returnPaths.files
  local fpaths = returnPaths.fpaths

  if files and #files > 0 then
    local button, i = ui.dialogs.filteredlist{
      title = 'Goto File ['..p.name..']',
      columns = {'Path'},
      items = files,
      width = 600,
      string_output = false
    }

    if button == 1 then
      io.open_file(fpaths[i])
    end
  end

end

function M.project_findcurrent()
  local root = M.findProjectRoot()
  local proj = nil
  local foundProject = false

  for k, v in pairs(M.projects) do
    if v["folders"] then

      for i,f in ipairs(v.folders) do
				f = translateFolder(f)

        if root == f then
          foundProject = true
          break
        end
      end

      if foundProject == true then
        proj = v
        proj.name = k
        break
      end
    end
  end

  return proj
end

function M.project_quickopen()
  local buffer = buffer
  if not buffer.filename then return end
  local root = M.findProjectRoot()
  local foundProject = false
  local proj = nil
  for k, v in pairs(M.projects) do
    if v["folders"] then

      for i,f in ipairs(v.folders) do
				f = translateFolder(f)

        if root == f then
          foundProject = true
          break
        end
      end

      if foundProject == true then
        proj = v
				proj.name = k
        break
      end
    end
  end

  if foundProject == false then
    proj = {
      build = {},
      types = {},
      exclude = {"/.git","/.svn","/obj","/bin"},
      folders = {
        root
      },
      name = "No Project"
    }

  end

  M.project_showfiles(proj)
end

local function getTagConf()
	local project = M.project_findcurrent()
	if project and project.tagging then
		local ext = buffer.filename:match('[^%.]+$')
		if project.tagging[ext] then
			return project.tagging[ext]
		elseif project.tagging.default then
			return project.tagging.default
		end
	end

	return nil
end

function M.goto_symbol()
  local buffer = buffer
  if not buffer.filename then return end
  local symbols = {}
	local CMD = M.defaultTagCmd..' "'..buffer.filename..'"'

	local tagConf = getTagConf()
	if tagConf then
		CMD = tagConf..' "'..buffer.filename..'"'
	end

	print("CMD: "..CMD)

  local p = io.popen(CMD)
  for line in p:read('*all'):gmatch('[^\r\n]+') do
    local name, file, line, ext,proto = line:match('^(%g+)%s+(%g+)%s+(%d+);"%s+(%g+)%s?(.*)')
    if name and line and ext then
			if not proto or proto:len() == 0 then proto = "NA" end

			if proto and proto:len() > 0 then
				proto = proto:gsub("signature:","")
			end
      symbols[#symbols + 1] = name
      symbols[#symbols + 1] = ext
      symbols[#symbols + 1] = line
      symbols[#symbols + 1] = proto
    end
  end
  if #symbols > 0 then
    local button, i = ui.dialogs.filteredlist{
      title = 'Goto Symbol', columns = {'Name', 'Type', 'Line', 'Sig'}, items = symbols, width=900
    }
    if button == 1 then
			buffer:goto_line(tonumber(symbols[(i * 4)-1]) - 1)
		end
  end
  p:close()
end

return M
