""" Serialize abstract wiring diagrams as GraphML.

Custom serialization of box, port, and wire values is supported. We depart
mildly from the GraphML spec by supporting JSON data attributes for GraphML
nodes, ports, and edges.

References:

- GraphML Primer: http://graphml.graphdrawing.org/primer/graphml-primer.html
- GraphML DTD: http://graphml.graphdrawing.org/specification/dtd.html
"""
module GraphML
export read_graphml, write_graphml

using DataStructures: OrderedDict
import JSON
using LightXML
using Nullables

using ..Wiring
import ..Wiring: PortEdgeData

# Data types
############

struct GraphMLKey
  id::String
  attr_name::String
  attr_type::String
  scope::String
  default::Nullable{Any}
end
GraphMLKey(id::String, attr_name::String, attr_type::String, scope::String) =
  GraphMLKey(id, attr_name, attr_type, scope, Nullable{Any}())

struct WriteState
  keys::OrderedDict{Tuple{String,String},GraphMLKey}
  WriteState() = new(OrderedDict{Tuple{String,String},GraphMLKey}())
end

struct ReadState
  keys::OrderedDict{String,GraphMLKey}
  BoxValue::Type
  PortValue::Type
  WireValue::Type
end

# Serialization
###############

""" Serialize a wiring diagram to GraphML.
"""
function write_graphml(diagram::WiringDiagram)::XMLDocument
  # Create XML document.
  xdoc = XMLDocument()
  finalizer(free, xdoc) # Destroy all children when document is GC-ed.
  xroot = create_root(xdoc, "graphml")
  set_attributes(xroot, Pair[
    "xmlns" => "http://graphml.graphdrawing.org/xmlns",
    "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
    "xsi:schemaLocation" => "http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd"
  ])
  
  # Create top-level graph element.
  xgraph = new_element("graph")
  set_attribute(xgraph, "edgedefault", "directed")
  
  # Recursively create nodes.
  state = WriteState()
  write_graphml_node(state, xgraph, "n", diagram)
  
  # Add attribute keys (data declarations). The keys are collected while
  # writing the nodes and are stored in the state object.
  for key in values(state.keys)
    write_graphml_key(xroot, key)
  end
  
  add_child(xroot, xgraph)
  return xdoc
end
function write_graphml(diagram::WiringDiagram, filename::String)
  LightXML.save_file(write_graphml(diagram), filename)
end

function write_graphml_node(
    state::WriteState, xgraph::XMLElement, id::String, diagram::WiringDiagram)
  # Create node element for wiring diagram and graph subelement to contain 
  # boxes and wires.
  xnode = new_child(xgraph, "node")
  set_attribute(xnode, "id", id)
  write_graphml_ports(state, xnode, diagram)
  
  xsubgraph = new_child(xnode, "graph")
  set_attribute(xsubgraph, "id", "$id:")
  
  # Add node elements for boxes.
  for v in box_ids(diagram)
    write_graphml_node(state, xsubgraph, "$id:n$v", box(diagram, v))
  end
  
  # Add edge elements for wires.
  in_id, out_id = input_id(diagram), output_id(diagram)
  node_id(port::Port) = port.box in (in_id, out_id) ? id : "$id:n$(port.box)"
  port_name(port::Port) = begin
    is_input = port.box in (in_id, out_id) ?
      port.box == in_id : port.kind == InputPort
    is_input ? "in:$(port.port)" : "out:$(port.port)"
  end
  for wire in wires(diagram)
    xedge = new_child(xsubgraph, "edge")
    set_attributes(xedge, Pair[
      "source"     => node_id(wire.source),
      "sourceport" => port_name(wire.source),
      "target"     => node_id(wire.target),
      "targetport" => port_name(wire.target),
    ])
    write_graphml_data(state, xedge, "edge", wire.value)
  end
end

function write_graphml_node(state::WriteState, xgraph::XMLElement, id::String, box::Box)
  xnode = new_child(xgraph, "node")
  set_attribute(xnode, "id", id)
  write_graphml_data(state, xnode, "node", box.value)
  write_graphml_ports(state, xnode, box)
end

function write_graphml_ports(state::WriteState, xnode::XMLElement, box::AbstractBox)
  # Write input ports.
  for (i, port) in enumerate(input_ports(box))
    xport = new_child(xnode, "port")
    set_attribute(xport, "name", "in:$i")
    write_graphml_data(state, xport, "port", Dict("portkind" => "input"))
    write_graphml_data(state, xport, "port", port)
  end
  # Write output ports.
  for (i, port) in enumerate(output_ports(box))
    xport = new_child(xnode, "port")
    set_attribute(xport, "name", "out:$i")
    write_graphml_data(state, xport, "port", Dict("portkind" => "output"))
    write_graphml_data(state, xport, "port", port)
  end
end

function write_graphml_key(xroot::XMLElement, key::GraphMLKey)
  xkey = new_child(xroot, "key")
  set_attributes(xkey, Pair[
    "id" => key.id,
    "for" => key.scope,
    "attr.name" => key.attr_name,
    "attr.type" => key.attr_type,
  ])
  if !isnull(key.default)
    xdefault = new_child(xkey, "default")
    set_content(xdefault, write_graphml_data_value(get(key.default)))
  end
end

function write_graphml_data(state::WriteState, xelem::XMLElement, scope::String, value)
  data = convert_to_graphml_data(value)
  for (attr_name, attr_value) in data
    # Retrieve or create key from state object.
    key = get!(state.keys, (attr_name, scope)) do
      nkeys = length(state.keys)
      id = "d$(nkeys+1)"
      attr_type = write_graphml_data_type(typeof(attr_value))
      GraphMLKey(id, attr_name, attr_type, scope)
    end
    
    # Write attribute data to <key> element.
    xdata = new_child(xelem, "data")
    set_attribute(xdata, "key", key.id)
    set_content(xdata, write_graphml_data_value(attr_value))
  end
end

write_graphml_data_type(::Type{Bool}) = "boolean"
write_graphml_data_type(::Type{<:Integer}) = "int"
write_graphml_data_type(::Type{<:Real}) = "double"
write_graphml_data_type(::Type{String}) = "string"
write_graphml_data_type(::Type{Symbol}) = "string"
write_graphml_data_type(::Type{Dict{String,T}}) where T = "json"
write_graphml_data_type(::Type{Vector{T}}) where T = "json"

write_graphml_data_value(x::Number) = string(x)
write_graphml_data_value(x::String) = x
write_graphml_data_value(x::Symbol) = string(x)
write_graphml_data_value(x::Dict) = JSON.json(x)
write_graphml_data_value(x::Vector) = JSON.json(x)

convert_to_graphml_data(value::Dict{String,T}) where T = value
convert_to_graphml_data(value) = Dict("value" => value)
convert_to_graphml_data(::Nothing) = Dict()
convert_to_graphml_data(value::Nullable) =
  isnull(value) ? Dict() : convert_to_graphml_data(get(value))

# Deserialization
#################

""" Deserialize a wiring diagram from GraphML.
"""
function read_graphml(::Type{BoxValue}, ::Type{PortValue}, ::Type{WireValue},
    xdoc::XMLDocument)::WiringDiagram where {BoxValue, PortValue, WireValue}
  xroot = root(xdoc)
  @assert name(xroot) == "graphml" "Root element of GraphML document must be <graphml>"
  xgraphs = xroot["graph"]
  @assert length(xgraphs) == 1 "Root element of GraphML document must contain exactly one <graph>"
  xgraph = xgraphs[1]
  xnodes = xgraph["node"]
  @assert length(xnodes) == 1 "Root graph of GraphML document must contain exactly one <node>"
  xnode = xnodes[1]
  
  keys = read_graphml_keys(xroot)
  state = ReadState(keys, BoxValue, PortValue, WireValue)
  diagram, ports = read_graphml_node(state, xnode)
  return diagram
end
function read_graphml(
    BoxValue::Type, PortValue::Type, WireValue::Type, filename::String)
  read_graphml(BoxValue, PortValue, WireValue, LightXML.parse_file(filename))
end

function read_graphml_node(state::ReadState, xnode::XMLElement)
  # Parse all the port elements.
  ports, input_ports, output_ports = read_graphml_ports(state, xnode)
  
  # Handle special cases: atomic boxes and malformed elements.
  xgraphs = xnode["graph"]
  if length(xgraphs) > 1
    error("Node element can contain at most one <graph> (subgraph element)")
  elseif isempty(xgraphs)
    data = read_graphml_data(state, xnode)
    value = convert_from_graphml_data(state.BoxValue, data)
    return (Box(value, input_ports, output_ports), ports)
  end
  xgraph = xgraphs[1] 
  
  # If we get here, we're reading a wiring diagram.
  diagram = WiringDiagram(input_ports, output_ports)
  diagram_ports = Dict{Tuple{String,String},Port}()
  for (key, port_data) in ports
    diagram_ports[key] = port_data.kind == InputPort ?
      Port(input_id(diagram), OutputPort, port_data.port) : 
      Port(output_id(diagram), InputPort, port_data.port)
  end
  
  # Read the node elements.
  for xsubnode in xgraph["node"]
    box, subports = read_graphml_node(state, xsubnode)
    v = add_box!(diagram, box)
    for (key, port_data) in subports
      diagram_ports[key] = Port(v, port_data.kind, port_data.port)
    end
  end
  
  # Read the edge elements.
  for xedge in xgraph["edge"]
    data = read_graphml_data(state, xedge)
    value = convert_from_graphml_data(state.WireValue, data)
    xsource = attribute(xedge, "source", required=true)
    xtarget = attribute(xedge, "target", required=true)
    xsourceport = attribute(xedge, "sourceport", required=true)
    xtargetport = attribute(xedge, "targetport", required=true)
    source = diagram_ports[(xsource, xsourceport)]
    target = diagram_ports[(xtarget, xtargetport)]
    add_wire!(diagram, Wire(value, source, target))
  end
  
  return (diagram, ports)
end

function read_graphml_ports(state::ReadState, xnode::XMLElement)
  ports = Dict{Tuple{String,String},PortEdgeData}()
  input_ports, output_ports = state.PortValue[], state.PortValue[]
  xnode_id = attribute(xnode, "id", required=true)
  xports = xnode["port"]
  for xport in xports
    xport_name = attribute(xport, "name", required=true)
    data = read_graphml_data(state, xport)
    port_kind = pop!(data, "portkind")
    value = convert_from_graphml_data(state.PortValue, data)
    if port_kind == "input"
      push!(input_ports, value)
      ports[(xnode_id, xport_name)] = PortEdgeData(InputPort, length(input_ports))
    elseif port_kind == "output"
      push!(output_ports, value)
      ports[(xnode_id, xport_name)] = PortEdgeData(OutputPort, length(output_ports))
    else
      error("Invalid port kind: $portkind")
    end
  end
  (ports, input_ports, output_ports)
end

function read_graphml_keys(xroot::XMLElement)
  keys = OrderedDict{String,GraphMLKey}()
  for xkey in xroot["key"]
    # Read attribute ID, name, type, and scope.
    attrs = attributes_dict(xkey)
    id = attrs["id"]
    attr_name = attrs["attr.name"]
    attr_type = get(attrs, "attr.type", "string")
    scope = get(attrs, "for", "all")
    
    # Read attribute default value.
    xdefaults = xkey["default"]
    default = if isempty(xdefaults)
      Nullable{Any}()
    else
      @assert length(xdefaults) == 1 "GraphML key can have at most one <default>"
      xdefault = xdefaults[1]
      Nullable(read_graphml_data_value(Val{Symbol(attr_type)}, content(xdefault)))
    end
    
    keys[id] = GraphMLKey(id, attr_name, attr_type, scope, default)
  end
  keys
end

function read_graphml_data(state::ReadState, xelem::XMLElement)
  # FIXME: We are not using the default values for the keys.
  data = Dict{String,Any}()
  for xdata in xelem["data"]
    xkey = attribute(xdata, "key", required=true)
    key = state.keys[xkey]
    data[key.attr_name] = read_graphml_data_value(
      Val{Symbol(key.attr_type)}, content(xdata))
  end
  data
end

read_graphml_data_value(::Type{Val{:boolean}}, s::String) = parse(Bool, lowercase(s))
read_graphml_data_value(::Type{Val{:int}}, s::String) = parse(Int, s)
read_graphml_data_value(::Type{Val{:long}}, s::String) = parse(Int, s)
read_graphml_data_value(::Type{Val{:float}}, s::String) = parse(Float32, s)
read_graphml_data_value(::Type{Val{:double}}, s::String) = parse(Float64, s)
read_graphml_data_value(::Type{Val{:string}}, s::String) = s
read_graphml_data_value(::Type{Val{:json}}, s::String) = JSON.parse(s)

convert_from_graphml_data(::Type{Dict}, data::Dict) = data
convert_from_graphml_data(::Type{Nothing}, data::Dict) = nothing

function convert_from_graphml_data(Value::Type, data::Dict)
  @assert length(data) == 1
  first(values(data))::Value
end
function convert_from_graphml_data(::Type{Symbol}, data::Dict)
  @assert length(data) == 1
  Symbol(first(values(data)))
end
function convert_from_graphml_data(::Type{Nullable{T}}, data::Dict) where T
  if isempty(data)
    Nullable{T}()
  else
    Nullable{T}(convert_from_graphml_data(T, data))
  end
end

end
