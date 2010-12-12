-----------------------------------------------------------------------------------
-- QuadTree.lua
-- Enrique García ( enrique.garcia.cota [AT] gmail [DOT] com ) - 12 Dec 2010
-- Quad Tree implementation in Lua
-----------------------------------------------------------------------------------

assert(Object~=nil and class~=nil, 'MiddleClass not detected. Please require it before using Apply')
assert(Brancy~=nil, 'QuadTree requires the middleclass-extras Branchy module in order to work. Please require it before QuadTree')

--------------------------------
--      PRIVATE STUFF
--------------------------------

-- returns true if two boxes intersect
local _intersect = function(ax1,ay1,aw,ah, bx1,by1,bw,bh)

  local ax2,ay2,bx2,by2 = ax1 + aw, ay1 + ah, bx1 + bw, by1 + bh
  return ax1 < bx2 and ax2 > bx1 and ay1 < by2 and ay2 > by1
end

-- returns true if a is contained in b
local _contained = function(ax1,ay1,aw,ah, bx1,by1,bw,bh)

  local ax2,ay2,bx2,by2 = ax1 + aw, ay1 + ah, bx1 + bw, by1 + bh
  return bx1 <= ax1 and bx2 >= ax2 and by1 <= ay1 and by2 >= ay2
end

-- create child nodes
local _createChildNodes = function(node)
  -- if the node is too small, or it already has nodes,, stop dividing it
  if(node.width * node.height < 16 or #(node.children) > 0) then return end

  local hw = node.width / 2.0
  local hh = node.height / 2.0

  node:addChild( QuadTree:new(hw, hh, node.x,    node.y) )
  node:addChild( QuadTree:new(hw, hh, node.x,    node.y) )
  node:addChild( QuadTree:new(hw, hh, node.x,    node.y+hh) )
  node:addChild( QuadTree:new(hw, hh, node.x+hw, node.y) )
  node:addChild( QuadTree:new(hw, hh, node.x+hw, node.y+hh) )
end

-- removes a node's children if they are all empty
local _emptyCheck
_emptyCheck = function(node, searchUp)
  if(not node) then return end
  if(node:getCount() == 0) then
    node.children = {}
    if(searchUp) then _emptyCheck(node.parent) end
  end
end

-- inserts an item on a node. Doesn't check whether it is the correct node
local _doInsert = function(node, item)
  if(node) then
    node.root.previous[item] = node
    node.root.unassigned[item] = nil
    node.items[item]= item
    node.itemsCount = node.itemsCount + 1
  end
  return node
end

-- removes an item from a node. It does not recursively traverse the node's children
-- if useNil is true, it completely removes the node from the quadtree
-- (it will not be available for updates later on)
-- if makeUnassigned is true, and the item isn't on the node, then the item 
-- is "put on hold" on the unassigned table on the root node. Otherwise it's completely removed
local _doRemove = function(node, item, makeUnassigned)
  if(node and node.items[item]) then
    node.root.previous[item]= nil
    node.items[item] = nil
    node.itemsCount = node.itemsCount - 1
    if(makeUnassigned==true) then
      node.root.unassigned[item]= item -- node might enter the quadtree again, via update
    end
  end
end

--------------------------------
--      PUBLIC STUFF
--------------------------------

QuadTree = class('QuadTree')

function QuadTree:initialize(width,height,x,y, isRoot)
  self.x, self.y, self.width, self.height = x or 0,y or 0,width,height

  self.items = setmetatable({}, {__mode = "k"})
  self.itemsCount = 0

  -- root node has two special properties:
  -- "previous" stores node assignments between updates
  -- "unassigned" is a list of items that are outside of the root
  if isRoot == true then
    self.previous = setmetatable({}, {__mode = "k"})
    self.unassigned = setmetatable({}, {__mode = "k"})
  end

end

function QuadTree:getBoundingBox()
  return self.x, self.y, self.width, self.height
end

-- Counts the number of items on a QuadTree, including child nodes
function QuadTree:getCount()
  local count = self.itemsCount
  for _,child in ipairs(self.children) do
    count = count + child:getCount()
  end
  return count
end

-- Gets items of the quadtree, including child nodes
function QuadTree:getAllItems()
  local results = {}
  for _,node in ipairs(self.children) do
    for _,item in ipairs(node:getAllItems()) do
      table.insert(results, item)
    end
  end
  for _,item in pairs(self.items) do
    table.insert(results, item)
  end
  return results
end

-- Inserts an item on the QuadTree. Returns the node containing it
function QuadTree:insert(item)
  return _doInsert(self:findNode(item), item)
end

-- Removes an item from the QuadTree. The item will be completely removed from the quadtree
-- update will not "see" it unless it is manually re-inserted
function QuadTree:remove(item)
  local node = self.root.previous[item]
  _doRemove(node, item, false)
  _emptyCheck(node, true)
end

-- Returns the items intersecting with a given area
function QuadTree:query(x,y,w,h)
  local results = {}
  local nx,ny,nw,nh

  for _,item in pairs(self.items) do
    if(_intersect(x,y,w,h, item:getBoundingBox())) then
      table.insert(results, item)
    end
  end

  for _,child in ipairs(self.children) do
    nx,ny,nw,nh = child:getBoundingBox()

    -- case 1: area is contained on the child completely
    -- add the items that intersect and then break the loop
    if(_contained(x,y,w,h, nx,ny,nw,nh)) then
      for _,item in ipairs(child:query(x,y,w,h)) do
        table.insert(results, item)
      end
      break

    -- case 2: child is completely contained on the area
    -- add all the items on the child and continue the loop
    elseif(_contained(nx,ny,nw,nh, x,y,w,h)) then
      for _,item in ipairs(child:getAllItems()) do
        table.insert(results, item)
      end

    -- case 3: node and area are intersecting
    -- add the items contained on the node's children and continue the loop
    elseif(_intersect(x,y,w,h, nx,ny,nw,nh)) then
      for _,item in ipairs(child:query(x,y,w,h)) do
        table.insert(results, item)
      end
    end
  end

  return results
end

-- Returns the smallest possible node that would contain a given item.
-- It does create additional nodes if needed, but it does *not* assign the node
-- if searchUp==true, search recursively up (parents), until root is reached
-- returns nil if the item isn't fully contained on the node, or searUp is true but
-- neither the node or its ancestors contain the item.
function QuadTree:findNode(item, searchUp)
  local x,y,w,h = item:getBoundingBox()
  if(_contained(x,y,w,h , self:getBoundingBox()) ) then
    -- the item is contained on the node. See if the node's descendants can hold the item
    _createChildNodes(self)
    for _,child in ipairs(self.children) do
      local descendant = child:findNode(item, false)
      if(descendant) then return descendant end
    end
    return self
  -- not contained on the node. Can we search up on the hierarchy?
  elseif(searchUp == true and self.parent) then
    return self.parent:findNode(item, true)
  else
    return nil
  end
end

-- Updates all the quadtree items
-- This method always updates the whole tree (starting from the root node)
function QuadTree:update()

  if(self.unassigned) then
    for _,item in pairs(self.unassigned) do
      self.root:insert(item)
    end
  end

  for _,item in pairs(self.items) do
    local newNode = self:findNode(item, true)
    if(self ~= newNode) then
      _doRemove(self, item, true)
      _doInsert(newNode, item)
    end
  end

  for _,child in ipairs(self.children) do
    child:update()
  end

  _emptyCheck(self, false)

end




