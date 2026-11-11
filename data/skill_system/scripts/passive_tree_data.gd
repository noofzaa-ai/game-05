class_name ZorxPassiveTreeData
extends Resource

@export var nodes: Array[ZorxTreeNodeData] = []
var by_id: Dictionary = {}
var adjacency: Dictionary = {}

func build() -> String:
 by_id.clear()
 adjacency.clear()
 for n in nodes:
  if n == null or n.id.is_empty() or by_id.has(n.id):
   return "Null, empty or duplicate tree node"
  by_id[n.id] = n
  adjacency[n.id] = []
 for n in nodes:
  for other in n.links:
   if not by_id.has(other):
    return "Unknown link: " + other
   if not other in adjacency[n.id]:
    adjacency[n.id].append(other)
   if not n.id in adjacency[other]:
    adjacency[other].append(n.id)
  for prerequisite in n.requires_all:
   if not by_id.has(prerequisite):
    return "Unknown prerequisite: " + prerequisite
 return ""

