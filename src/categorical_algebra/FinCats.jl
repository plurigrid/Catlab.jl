""" 2-category of finitely presented categories.

This module is for the 2-category **Cat** what the module [`FinSets`](@ref) is
for the category **Set**: a finitary, combinatorial setting where explicit
calculations can be carried out. We emphasize that the prefix `Fin` means
"finitely presented," not "finite," as finite categories are too restrictive a
notion for many purposes. For example, the free category on a graph is finite if
and only if the graph is DAG, which is a fairly special condition. This usage of
`Fin` is also consistent with `FinSet` because for sets, being finite and being
finitely presented are equivalent.
"""
module FinCats
export FinCat, FinCatGraph, Path, ob_generator, hom_generator,
  ob_generator_name, hom_generator_name, ob_generators, hom_generators,
  equations, is_discrete, is_free, graph, edges, src, tgt, presentation,
  FinFunctor, FinDomFunctor, is_functorial, functoriality_failures,
  collect_ob, collect_hom, force, make_map,
  FinTransformation, components, is_natural, is_initial,dom_to_graph

using StructEquality
using Reexport
using StaticArrays: SVector
using DataStructures: IntDisjointSets, in_same_set, num_groups

using ACSets
using ...GATs
import ...GATs: equations
using ...Theories: ThCategory, ThSchema, ThPtCategory, ThPtSchema, ObExpr, HomExpr, AttrExpr, AttrTypeExpr, FreeSchema, FreePtCategory, zeromap
import ...Theories: dom, codom, id, compose, ⋅, ∘
using ...Graphs
import ...Graphs: edges, src, tgt, enumerate_paths
@reexport using ..Categories
import ..Categories: CatSize, ob, hom, ob_map, hom_map, component, op
# Categories
############

""" Size of a finitely presented category.
"""
struct FinCatSize <: CatSize end

""" A finitely presented (but not necessarily finite!) category.
"""
const FinCat{Ob,Hom} = Cat{Ob,Hom,FinCatSize}

FinCat(g::HasGraph, args...; kw...) = FinCatGraph(g, args...; kw...)
FinCat(pres::Presentation, args...; kw...) =
  FinCatPresentation(pres, args...; kw...)

""" Object generators of finitely presented category.

The object generators of finite presented category are almost always the same as
the objects. In principle, however, it is possible to have equations between
objects, so that there are fewer objects than object generators.
"""
function ob_generators end

""" Morphism generators of finitely presented category.
"""
function hom_generators end

""" Coerce or look up object generator in a finitely presented category.

Because object generators usually coincide with objects, the default method for
[`ob`](@ref) in finitely presented categories simply calls this function.
"""
function ob_generator end

ob(C::FinCat, x) = ob_generator(C, x)

""" Coerce or look up morphism generator in a finitely presented category.

Since morphism generators often have a different data type than morphisms (e.g.,
in a free category on a graph, the morphism generators are edges and the
morphisms are paths), the return type of this function is generally different
than that of [`hom`](@ref).
"""
function hom_generator end

""" Name of object generator, if any.

When object generators have names, this function is a one-sided inverse to
[`ob_generator`](@ref) in that `ob_generator(C, ob_generator_name(C, x)) == x`.
"""
function ob_generator_name end

""" Name of morphism generator, if any.

When morphism generators have names, this function is a one-sided inverse to
[`hom_generator`](@ref). See also: [`ob_generator_name`](@ref).
"""
function hom_generator_name end

# Second clause should be superfluous but we'll include it anyway.
Base.isempty(C::FinCat) = isempty(ob_generators(C)) && isempty(hom_generators(C))

""" Is the category discrete?

A category is *discrete* if it is has no non-identity morphisms.
"""
is_discrete(C::FinCat) = isempty(hom_generators(C))

""" Is the category freely generated?
"""
is_free(C::FinCat) = isempty(equations(C))

"""Graph underlying a finitely presented category whose 
object and
hom generators are indexable, other
than one explicitly generated by a graph.
"""
function graph(C::FinCat;maps::Bool=false,inv::Bool=false) 
  g = Graph() 
  obgens = ob_generators(C)
  homgens = hom_generators(C)
  add_vertices!(g,length(obgens))
  s(f) = only(indexin([dom(f)],obgens))
  t(f) = only(indexin([codom(f)],obgens))
  add_edges!(g,Int[s(f) for f in homgens],Int[t(f) for f in homgens])
  maps || return g
  inv ? (g, Dict(obgens[i] => i for i in 1:length(obgens)),
  Dict(homgens[i] => i for i in 1:length(homgens))) :
  (g, Dict(pairs(obgens)), Dict(pairs(homgens)))
end
# Opposite FinCats
#-----------------

const OppositeFinCat{Ob,Hom} = OppositeCat{Ob,Hom,FinCatSize}

ob_generators(C::OppositeFinCat) = ob_generators(C.cat)
#wrong for presentations, redefined below
hom_generators(C::OppositeFinCat) = hom_generators(C.cat)

ob_generator(C::OppositeCat, x) = ob_generator(C.cat, x)
hom_generator(C::OppositeCat, f) = hom_generator(C.cat, f)

"""
Reverses the domain and codomain of certain types in a presentation,
for use in an opposite category.
"""
function Base.reverse(p::Presentation,types::Vector{Symbol})
  s = p.syntax
  newPres = Presentation(s)
  for g in generators(p)
    t = gat_typeof(g)
    if t in types 
      add_generator!(newPres,getproperty(s,t)(nameof(g),codom(g),dom(g)))  
    else add_generator!(newPres,g) 
    end
  end
  newPres
end
presentation(C::OppositeCat) = reverse(presentation(C.cat),[:Hom])
# Categories on graphs
######################

""" Abstract type for category backed by finite generating graph.
"""
abstract type FinCatGraph{G,Ob,Hom} <: FinCat{Ob,Hom} end

""" Generating graph for a finitely presented category.
"""
graph(C::FinCatGraph;maps=false,kw...) = maps ? (C.graph, 1:nv(C.graph), 1:ne(C.graph)) : C.graph
  
graph(C::OppositeCat;kw...) = reverse(graph(op(C);kw...))

ob_generators(C::FinCatGraph) = vertices(graph(C))
hom_generators(C::FinCatGraph) = edges(graph(C))

ob_generator(C::FinCatGraph, x) = all(has_vertex(graph(C), x)) ? x :
  error("Vertex $x not contained in graph $(graph(C))")
hom_generator(C::FinCatGraph, f) = all(has_edge(graph(C), f)) ? f :
  error("Edge $f not contained in graph $(graph(C))")

ob_generator(C::FinCatGraph, x::Union{AbstractString,Symbol}) =
  vertex_named(graph(C), x)
hom_generator(C::FinCatGraph, f::Union{AbstractString,Symbol}) =
  edge_named(graph(C), f)
ob_generator_name(C::FinCatGraph, x) = vertex_name(graph(C), x)
hom_generator_name(C::FinCatGraph, f) = edge_name(graph(C), f)

# FIXME: These functions should go somewhere else, maybe in `Graphs`.
# Better yet, we should have a notion of "primary key" to avoid this.
vertex_name(G::HasGraph, v) = v
edge_name(G::HasGraph, e) = e
function vertex_named end
function edge_named end

function Base.show(io::IO, C::FinCatGraph)
  print(io, "FinCat(")
  show(io, graph(C))
  print(io, ", [")
  join(io, equations(C), ", ")
  print(io, "])")
end

# Paths in graphs
#----------------

""" Path in a graph.

The path is allowed to be empty but always has definite start and end points
(source and target vertices).
"""
@struct_hash_equal struct Path{V,E,Edges<:AbstractVector{E}}
  edges::Edges
  src::V
  tgt::V
end
edges(path::Path) = path.edges
src(path::Path) = path.src
tgt(path::Path) = path.tgt

function Path(g::HasGraph, es::AbstractVector)
  !isempty(es) || error("Nonempty edge list needed for nontrivial path")
  all(e -> has_edge(g, e), es) || error("Path has edges not contained in graph")
  Path(es, src(g, first(es)), tgt(g, last(es)))
end

function Path(g::HasGraph, e)
  has_edge(g, e) || error("Edge $e not contained in graph $g")
  Path(SVector(e), src(g,e), tgt(g,e))
end

function Base.empty(::Type{Path}, g::HasGraph, v::T) where T
  has_vertex(g, v) || error("Vertex $v not contained in graph $g")
  Path(SVector{0,T}(), v, v)
end

Base.reverse(p::Path) = Path(reverse(edges(p)), tgt(p), src(p))

function Base.vcat(p1::Path, p2::Path)
  tgt(p1) == src(p2) ||
    error("Path start/end points do not match: $(tgt(p1)) != $(src(p2))")
  Path(vcat(edges(p1), edges(p2)), src(p1), tgt(p2))
end

function Base.show(io::IO, path::Path)
  print(io, "Path(")
  show(io, edges(path))
  print(io, ": $(src(path)) → $(tgt(path)))")
end

""" Abstract type for category whose morphisms are paths in a graph.

(Or equivalence classes of paths in a graph, but we compute with
"""
const FinCatPathGraph{G,V,E} = FinCatGraph{G,V,Path{V,E}}

dom(C::FinCatPathGraph, e) = src(graph(C), e)
dom(C::FinCatPathGraph, path::Path) = src(path)
codom(C::FinCatPathGraph, e) = tgt(graph(C), e)
codom(C::FinCatPathGraph, path::Path) = tgt(path)

id(C::FinCatPathGraph, x) = empty(Path, graph(C), x)
compose(C::FinCatPathGraph, fs...) =
  reduce(vcat, coerce_path(graph(C), f) for f in fs)

hom(C::FinCatPathGraph, f) = coerce_path(graph(C), f)

coerce_path(g::HasGraph, path::Path) = path
coerce_path(g::HasGraph, x) = Path(g, x)

# Free category on graph
#-----------------------

""" Free category generated by a finite graph.

The objects of the free category are vertices in the graph and the morphisms are
(possibly empty) paths.
"""
@struct_hash_equal struct FreeCatGraph{G<:HasGraph} <: FinCatPathGraph{G,Int,Int}
  graph::G
end

FinCatGraph(g::HasGraph) = FreeCatGraph(g)

is_free(::FreeCatGraph) = true
equations(::FreeCatGraph) = []

function Base.show(io::IO, C::FreeCatGraph)
  print(io, "FinCat(")
  show(io, graph(C))
  print(io, ")")
end

# Category on graph with equations
#---------------------------------

""" Category presented by a finite graph together with path equations.

The objects of the category are vertices in the graph and the morphisms are
paths, quotiented by the congruence relation generated by the path equations.
See (Spivak, 2014, *Category theory for the sciences*, §4.5).
"""
@struct_hash_equal struct FinCatGraphEq{G<:HasGraph,Eqs<:AbstractVector{<:Pair}} <:
    FinCatPathGraph{G,Int,Int}
  graph::G
  equations::Eqs
end

equations(C::FinCatGraphEq) = C.equations
equations(C::OppositeCat) = map(x->reverse(x.first)=>reverse(x.second),equations(C.cat))

function FinCatGraph(g::HasGraph, eqs::AbstractVector)
  eqs = map(eqs) do eq
    lhs, rhs = coerce_path(g, first(eq)), coerce_path(g, last(eq))
    (src(lhs) == src(rhs) && tgt(lhs) == tgt(rhs)) ||
      error("Paths $lhs and $rhs in equation do not have equal (co)domains")
    lhs => rhs
  end
  FinCatGraphEq(g, eqs)
end

# Symbolic categories
#####################

""" Category defined by a `Presentation` object.

The presentation type can, of course, be a category (`Theories.Category`). It
can also be a schema (`Theories.Schema`). In this case, the schema's objects and
attribute types are regarded as the category's objects and the schema's
morphisms, attributes, and attribute types as the category's morphisms (where
the attribute types are identity morphisms). When the schema is formalized as a
profunctor whose codomain category is discrete, this amounts to taking the
collage of the profunctor.
"""
@struct_hash_equal struct FinCatPresentation{T,Ob,Hom} <: FinCat{Ob,Hom}
  presentation::Presentation{T}
end

function FinCatPresentation(pres::Presentation{T}) where T
  S = pres.syntax
  FinCatPresentation{T,S.Ob,S.Hom}(pres)
end
function FinCatPresentation(pres::Presentation{ThSchema})
  S = pres.syntax
  Ob = Union{S.Ob, S.AttrType}
  #AttrTypes can be homs because...Something about their identity morphisms?
  Hom = Union{S.Hom, S.Attr, S.AttrType}
  FinCatPresentation{ThSchema,Ob,Hom}(pres)
end
#=
#TBD whether this guy should get explicit generators for the 
#zero object and homs. These are legitimate generators when seen qua
#category but not qua pointed category...
function FinCatPresentation(pres::Presentation{ThPtCategory})
  S = pres.syntax
  Ob = S.Ob
  Hom = Union{S.Hom,S.ZeroHom}
  FinCatPresentation{ThPtCategory,Ob,Hom}(pres)
end
=#

#better to inherit from schema to avoid this kind of thing
function FinCatPresentation(pres::Presentation{ThPtSchema})
  S = pres.syntax
  Ob = Union{S.Ob, S.AttrType}
  Hom = Union{S.Hom, S.Attr, S.AttrType}
  FinCatPresentation{ThPtSchema,Ob,Hom}(pres)
end
function hom_generators(C::OppositeCat{Ob,Hom,FinCatSize,Ct}) where {Ob,Hom,Ct<:FinCatPresentation}
  S = presentation(C).syntax
  map(x->S.Hom(nameof(x),codom(x),dom(x)),hom_generators(C.cat))
end
"""
Computes the graph generating a finitely
presented category. Ignores any attribute
side and any equations. Optionally returns
the mappings from generators to their indices
in the resulting graph.
"""
#=
function graph(C::FinCatPresentation;maps::Bool=false,inv::Bool=false)
  g = Graph()
  pres = C.presentation
  obgens = pres.generators[:Ob]
  homgens = pres.generators[:Hom]
  nob = length(obgens)
  add_parts!(g,:V,nob)
  map(pres.generators[:Hom]) do f
    i,j = indexin([dom(f),codom(f)],pres.generators[:Ob])
    add_edge!(g,i,j)
  end
  maps || return g
  inv ? (g, Dict(obgens[i] => i for i in 1:length(obgens)),
  Dict(homgens[i] => i for i in 1:length(homgens))) :
  (g, Dict(pairs(obgens)), Dict(pairs(homgens)))
end
=#
presentation(C::FinCatPresentation) = C.presentation

ob_generators(C::FinCatPresentation) = generators(presentation(C), :Ob)
ob_generators(C::Union{FinCatPresentation{ThSchema},FinCatPresentation{ThPtSchema}}) = let P = presentation(C)
  vcat(generators(P, :Ob), generators(P, :AttrType))
end

hom_generators(C::FinCatPresentation) = generators(presentation(C), :Hom)
hom_generators(C::Union{FinCatPresentation{ThSchema},FinCatPresentation{ThPtSchema}}) = let P = presentation(C)
  vcat(generators(P, :Hom), generators(P, :Attr))
end
equations(C::FinCatPresentation) = equations(presentation(C))

ob_generator(C::FinCatPresentation, x) = ob(C, presentation(C)[x])
ob_generator(C::FinCatPresentation, x::GATExpr{:generator}) = ob(C, x)
ob_generator_name(C::FinCatPresentation, x::GATExpr{:generator}) = first(x)

hom_generator(C::FinCatPresentation, f) = hom(C, presentation(C)[f])
hom_generator(C::FinCatPresentation, f::GATExpr{:generator}) = hom(C, f)
hom_generator_name(C::FinCatPresentation, f::GATExpr{:generator}) = first(f)

ob(C::FinCatPresentation, x::GATExpr) =
  gat_typeof(x) == :Ob ? x : error("Expression $x is not an object")
ob(C::Union{FinCatPresentation{ThSchema},FinCatPresentation{ThPtSchema}}, x::GATExpr) =
  gat_typeof(x) ∈ (:Ob, :AttrType) ? x :
    error("Expression $x is not an object or attribute type")

hom(C::FinCatPresentation, f) = hom_generator(C, f)
hom(C::FinCatPresentation, fs::AbstractVector) =
  mapreduce(f -> hom(C, f), compose, fs)
hom(C::FinCatPresentation, f::GATExpr) =
  gat_typeof(f) == :Hom ? f : error("Expression $f is not a morphism")
hom(::Union{FinCatPresentation{ThSchema},FinCatPresentation{ThPtSchema}}, f::GATExpr) =
  gat_typeof(f) ∈ (:Hom, :Attr, :AttrType,:ZeroHom,:ZeroAttr) ? f :
    error("Expression $f is not a morphism or attribute")

id(C::FinCatPresentation{ThSchema}, x::AttrTypeExpr) = x
compose(C::FinCatPresentation{ThSchema}, f::AttrTypeExpr, g::AttrTypeExpr) =
  (f == g) ? f : error("Invalid composite of attribute type identities: $f != $g")

function Base.show(io::IO, C::FinCatPresentation)
  print(io, "FinCat(")
  show(io, presentation(C))
  print(io, ")")
end

# Functors
##########

""" A functor out of a finitely presented category.
"""
const FinDomFunctor{Dom<:FinCat,Codom<:Cat} = Functor{Dom,Codom}

FinDomFunctor(maps::NamedTuple{(:V,:E)}, dom::FinCatGraph, codom::Cat) =
  FinDomFunctor(maps.V, maps.E, dom, codom)

function FinDomFunctor(ob_map, dom::FinCat, codom::Cat{Ob,Hom}) where {Ob,Hom}
  is_discrete(dom) ||
    error("Morphism map omitted by domain category is not discrete: $dom")
  FinDomFunctor(ob_map, empty(ob_map, Hom), dom, codom)
end
FinDomFunctor(ob_map, ::Nothing, dom::FinCat, codom::Cat) =
  FinDomFunctor(ob_map, dom, codom)

function hom_map(F::FinDomFunctor, path::Path)
  C, D = dom(F), codom(F)
  path = decompose(C, path)
  #below shouldn't be needed anymore.
  edg = map(e->hom_map(F,e),edges(path))
  for e in edg if e isa FreeSchema.Attr{:nothing} return e end end
  reduce((gs...) -> compose(D, gs...),
            edg, init=id(D, ob_map(F, src(path))))
end
decompose(C::FinCatGraph, path::Path) = path
decompose(C::OppositeCat, path::Path) = reverse(path)

function hom_map(F::FinDomFunctor, f::GATExpr{:compose})
  C, D = dom(F), codom(F)
  mapreduce(f -> hom_map(F, f), (gs...) -> compose(D, gs...), decompose(C, f))
end
decompose(C::FinCatPresentation, f::GATExpr{:compose}) = args(f)
decompose(C::OppositeCat, f::GATExpr{:compose}) = reverse(decompose(C.cat, f))

function hom_map(F::FinDomFunctor, f::GATExpr{:id})
  id(codom(F), ob_map(F, dom(f)))
end

(F::FinDomFunctor)(expr::ObExpr) = ob_map(F, expr)
(F::FinDomFunctor)(expr::HomExpr) = hom_map(F, expr)

Categories.show_type_constructor(io::IO, ::Type{<:FinDomFunctor}) =
  print(io, "FinDomFunctor")

""" Collect assignments of functor's object map as a vector.
"""
collect_ob(F::FinDomFunctor) = map(x -> ob_map(F, x), ob_generators(dom(F)))

""" Collect assignments of functor's morphism map as a vector.
"""
collect_hom(F::FinDomFunctor) = map(f -> hom_map(F, f), hom_generators(dom(F)))

""" Is the purported functor on a presented category functorial?

This function checks that functor preserves domains and codomains. When
`check_equations` is `true` (the default is `false`), it also purports to check
that the functor preserves all equations in the domain category. No nontrivial 
checks are currently implemented, so this only functions for identity functors.

See also: [`functoriality_failures'](@ref) and [`is_natural`](@ref).
"""
function is_functorial(F::FinDomFunctor; kw...)
  failures = functoriality_failures(F; kw...)
  all(isempty, failures)
end

""" Failures of the purported functor on a presented category to be functorial.

Similar to [`is_functorial`](@ref) (and with the same caveats) but returns
iterators of functoriality failures: one for domain incompatibilities, one for
codomain incompatibilities, and one for equations that are not satisfied.
"""
function functoriality_failures(F::FinDomFunctor; check_equations::Bool=false)
  C, D = dom(F), codom(F)
  bad_dom = Iterators.filter(hom_generators(C)) do f 
    dom(D, hom_map(F, f)) != ob_map(F, dom(C,f))
  end 
  bad_cod = Iterators.filter(hom_generators(C)) do f 
    codom(D, hom_map(F, f)) != ob_map(F, codom(C,f))
  end
  bad_eqs = if check_equations
    # TODO: Currently this won't check for nontrivial equalities
    Iterators.filter(equations(C)) do (lhs,rhs)
      !is_hom_equal(D,hom_map(F,lhs),hom_map(F,rhs))
    end
  else () end
  (bad_dom, bad_cod, bad_eqs)
end

#XX:make more principled using make_map or something similar
function Base.map(F::Functor{<:FinCat,<:TypeCat}, f_ob, f_hom)
  C = dom(F)
  FinDomFunctor(map(x -> f_ob(ob_map(F, x)), ob_generators(C)),
                map(f -> f_hom(hom_map(F, f)), hom_generators(C)), C)
end
function Base.map(F::Functor{<:FinCatPresentation,<:TypeCat}, f_ob, f_hom)
  C = dom(F)
  FinDomFunctor(Dict(x => f_ob(ob_map(F, x)) for x in ob_generators(C)),
                Dict(f => f_hom(hom_map(F, f)) for f in hom_generators(C)), C)
end

""" A functor between finitely presented categories.
"""
const FinFunctor{Dom<:FinCat,Codom<:FinCat} = FinDomFunctor{Dom,Codom}

FinFunctor(maps, dom::FinCat, codom::FinCat) = FinDomFunctor(maps, dom, codom)
FinFunctor(ob_map, hom_map, dom::FinCat, codom::FinCat) =
  FinDomFunctor(ob_map, hom_map, dom, codom)
FinFunctor(ob_map, hom_map, dom::Presentation, codom::Presentation) =
  FinDomFunctor(ob_map, hom_map, FinCat(dom), FinCat(codom))

Categories.show_type_constructor(io::IO, ::Type{<:FinFunctor}) =
  print(io, "FinFunctor")

# Mapping-based functors
#-----------------------

""" Functor out of a finitely presented category given by explicit mappings.
"""
@struct_hash_equal struct FinDomFunctorMap{Dom<:FinCat, Codom<:Cat,
    ObMap, HomMap} <: FinDomFunctor{Dom,Codom}
  ob_map::ObMap
  hom_map::HomMap
  dom::Dom
  codom::Codom
end
FinDomFunctorMap(ob_map::Union{AbstractVector{Ob},AbstractDict{<:Any,Ob}},
                 hom_map::Union{AbstractVector{Hom},AbstractDict{<:Any,Hom}},
                 dom::FinCat) where {Ob,Hom} =
  FinDomFunctorMap(ob_map, hom_map, dom, TypeCat(Ob, Hom))

function FinDomFunctor(ob_map::Union{AbstractVector{Ob},AbstractDict{<:Any,Ob}},
                       hom_map::Union{AbstractVector{Hom},AbstractDict{<:Any,Hom}},
                       dom::FinCat, codom::Union{Cat,Nothing}=nothing) where {Ob,Hom}
  length(ob_map) == length(ob_generators(dom)) ||
    error("Length of object map $ob_map does not match domain $dom")
  length(hom_map) == length(hom_generators(dom)) ||
    error("Length of morphism map $hom_map does not match domain $dom")
  if isnothing(codom)
    ob_map = mappairs(x -> ob_key(dom, x), identity, ob_map)
    hom_map = mappairs(f -> hom_key(dom, f), identity, hom_map)
    FinDomFunctorMap(ob_map, hom_map, dom)
  else
    ob_map = mappairs(x -> ob_key(dom, x), y -> ob(codom, y), ob_map)
    hom_map = mappairs(f -> hom_key(dom, f), g -> hom(codom, g), hom_map)
    FinDomFunctorMap(ob_map, hom_map, dom, codom)
  end
end

ob_key(C::FinCat, x) = ob_generator(C, x)
hom_key(C::FinCat, f) = hom_generator(C, f)
ob_map(F::FinDomFunctorMap) = F.ob_map
hom_map(F::FinDomFunctorMap) = F.hom_map

# Use generator names, rather than generators themselves, for Dict keys!
# XXX: Should this be enforced?
ob_key(C::FinCatPresentation, x) = presentation_key(x)
hom_key(C::FinCatPresentation, f) = presentation_key(f)
presentation_key(name::Union{AbstractString,Symbol}) = name
presentation_key(expr::GATExpr{:generator}) = first(expr)
ob_key(C::OppositeFinCat, x) = ob_key(C.cat,x)
hom_key(C::OppositeFinCat, f) = hom_key(C.cat,f)

Categories.do_ob_map(F::FinDomFunctorMap, x) = F.ob_map[ob_key(F.dom, x)]
Categories.do_hom_map(F::FinDomFunctorMap, f) = F.hom_map[hom_key(F.dom, f)]

collect_ob(F::FinDomFunctorMap) = collect_values(F.ob_map)
collect_hom(F::FinDomFunctorMap) = collect_values(F.hom_map)
collect_values(vect::AbstractVector) = vect
collect_values(dict::AbstractDict) = collect(values(dict))

op(F::FinDomFunctorMap) = FinDomFunctorMap(F.ob_map, F.hom_map,
                                           op(dom(F)), op(codom(F)))

""" Force evaluation of lazily defined function or functor.
The resulting ob_map and hom_map are guaranteed to have 
valtype or eltype, as appropriate, equal to Ob and Hom,
respectively. 
"""
function force(F::FinDomFunctor, Obtype::Type=Any, Homtype::Type=Any;params=Dict())
  C = dom(F)
  FinDomFunctorMap(
    make_map(x -> ob_map(F, x), ob_generators_simple(C), Obtype),
    make_map(hom_generators_simple(C), Homtype) do f 
     haskey(params,f) ? params[f] : hom_map(F,f) end , 
    C)
end
force(F::FinDomFunctorMap) = 
  FinDomFunctorMap(F.ob_map,
    mapvals(F.hom_map,keys=true) do h,f
    haskey(params,h) ? params[h] : hom_map(F,h) end,
    F.dom,F.codom)

ob_generators_simple(C::FinCatPresentation) =
  map(nameof,ob_generators(C))
ob_generators_simple(C::FinCat) = ob_generators(C)
hom_generators_simple(C::FinCatPresentation) =
  map(nameof,hom_generators(C))
hom_generators_simple(C::FinCat) = hom_generators(C)
function Categories.do_compose(F::FinDomFunctorMap, G::FinDomFunctorMap)
  FinDomFunctorMap(mapvals(x -> ob_map(G, x), F.ob_map),
                   mapvals(f -> hom_map(G, f), F.hom_map), dom(F), codom(G))
end

"""
Reinterpret a functor on a finitely presented category
as a functor on the equivalent category (ignoring equations)
free on a graph. Could be considered as a type of force?
"""
function dom_to_graph(F::FinDomFunctor{<:FinCatPresentation,<:Cat{Ob,Hom}}) where {Ob,Hom}
  g, obs, homs = graph(dom(F),maps=true)
  C = FinCat(g)
  FinDomFunctorMap(Ob[ob_map(F,obs[i]) for i in 1:length(obs)],Hom[hom_map(F,homs[i]) for i in 1:length(homs)],C,codom(F))
end
dom_to_graph(F::FinDomFunctor) = F
function Base.show(io::IO, F::T) where T <: FinDomFunctorMap
  Categories.show_type_constructor(io, T); print(io, "(")
  show(io, F.ob_map)
  print(io, ", ")
  show(io, F.hom_map)
  print(io, ", ")
  Categories.show_domains(io, F)
  print(io, ")")
end

# Natural transformations
#########################

""" A natural transformation whose domain category is finitely generated.

This type is for natural transformations ``α: F ⇒ G: C → D`` such that the
domain category ``C`` is finitely generated. Such a natural transformation is
given by a finite amount of data (one morphism in ``D`` for each generating
object of ``C``) and its naturality is verified by finitely many equations (one
equation for each generating morphism of ``C``).
"""
const FinTransformation{C<:FinCat,D<:Cat,Dom<:FinDomFunctor,Codom<:FinDomFunctor} =
  Transformation{C,D,Dom,Codom}

FinTransformation(F, G; components...) = FinTransformation(components, F, G)

""" Components of a natural transformation.
"""
components(α::FinTransformation) =
  make_map(x -> component(α, x), ob_generators(dom_ob(α)))

""" Is the transformation between `FinDomFunctors` a natural transformation?

This function uses the fact that to check whether a transformation is natural,
it suffices to check the naturality equations on a generating set of morphisms
of the domain category. In some cases, checking the equations may be expensive
or impossible. When the keyword argument `check_equations` is `false`, only the
domains and codomains of the components are checked.

See also: [`is_functorial`](@ref).
"""
function is_natural(α::FinTransformation; check_equations::Bool=true)
  F, G = dom(α), codom(α)
  C, D = dom(F), codom(F) # == dom(G), codom(G)
  all(ob_generators(C)) do c
    α_c = α[c]
    dom(D, α_c) == ob_map(F,c) && codom(D, α_c) == ob_map(G,c)
  end || return false

  if check_equations
    all(hom_generators(C)) do f
      Ff, Gf = hom_map(F,f), hom_map(G,f)
      α_c, α_d = α[dom(C,f)], α[codom(C,f)]
      is_hom_equal(D, compose(D, α_c, Gf), compose(D, Ff, α_d))
    end || return false
  end

  true
end

function check_transformation_domains(F::Functor, G::Functor)
  # XXX: Equality of TypeCats is too strict, so for now we are punting on
  # (co)domain checks in that case.
  C, C′ = dom(F), dom(G)
  (C isa TypeCat && C′ isa TypeCat) || C == C′ ||
    error("Mismatched domains in functors $F and $G")
  D, D′ = codom(F), codom(G)
  (D isa TypeCat && D′ isa TypeCat) || D == D′ ||
    error("Mismatched codomains in functors $F and $G")
  (C, D)
end

# Mapping-based transformations
#------------------------------

""" Natural transformation with components given by explicit mapping.
"""
@struct_hash_equal struct FinTransformationMap{C<:FinCat,D<:Cat,
    Dom<:FinDomFunctor{C,D},Codom<:FinDomFunctor,Comp} <: FinTransformation{C,D,Dom,Codom}
  components::Comp
  dom::Dom
  codom::Codom
end

function FinTransformation(components::Union{AbstractVector,AbstractDict},
                           F::FinDomFunctor, G::FinDomFunctor)
  C, D = check_transformation_domains(F, G)
  length(components) == length(ob_generators(C)) ||
    error("Incorrect number of components in $components for domain category $C")
  components = mappairs(x -> ob_key(C,x), f -> hom(D,f), components)
  FinTransformationMap(components, F, G)
end

component(α::FinTransformationMap, x) = α.components[ob_key(dom_ob(α), x)]
components(α::FinTransformationMap) = α.components

op(α::FinTransformationMap) = FinTransformationMap(components(α),
                                                   op(codom(α)), op(dom(α)))

function Categories.do_compose(α::FinTransformationMap, β::FinTransformation)
  F = dom(α)
  D = codom(F)
  FinTransformationMap(mapvals(α.components, keys=true) do c, f
                         compose(D, f, component(β, c))
                       end, F, codom(β))
end

function Categories.do_composeH(F::FinDomFunctorMap, β::Transformation)
  G, H = dom(β), codom(β)
  FinTransformationMap(mapvals(c -> component(β, c), F.ob_map),
                       compose(F, G, strict=false), compose(F, H, strict=false))
end

function Categories.do_composeH(α::FinTransformationMap, H::Functor)
  F, G = dom(α), codom(α)
  FinTransformationMap(mapvals(f->hom_map(H,f),α.components),
                      compose(F, H, strict=false), compose(G, H, strict=false))
end

function Base.show(io::IO, α::FinTransformationMap)
  print(io, "FinTransformation(")
  show(io, components(α))
  print(io, ", ")
  Categories.show_domains(io, α, recurse=false)
  print(io, ", ")
  Categories.show_domains(io, dom(α))
  print(io, ")")
end

# Initial functors
##################

"""
Dual to a [final functor](https://ncatlab.org/nlab/show/final+functor), an
*initial functor* is one for which pulling back diagrams along it does not
change the limits of these diagrams.

This amounts to checking, for a functor C->D, that, for every object d in
Ob(D), the comma category (F/d) is connected.
"""
function is_initial(F::FinFunctor)::Bool
  Gₛ, Gₜ = graph(dom(F)), graph(codom(F))
  pathₛ, pathₜ = enumerate_paths.([Gₛ, Gₜ])

  function connected_nonempty_slice(t::Int)::Bool
    paths_into_t = incident(pathₜ, t, :tgt)
    # Generate slice objects
    ob_slice = Pair{Int,Vector{Int}}[] # s ∈ Ob(S) and a path ∈ T(F(s), t)
    for s in vertices(Gₛ)
      paths_s_to_t = incident(pathₜ, ob_map(F,s), :src) ∩ paths_into_t
      append!(ob_slice, [s => pathₜ[p, :eprops] for p in paths_s_to_t])
    end

    # Empty case
    isempty(ob_slice) && return false

    """
    For two slice objects (m,pₘ) and (n,pₙ) check for a morphism f ∈ S(M,N) such
    that there is a commutative triangle pₘ = f;pₙ
    """
    function check_pair(i::Int, j::Int)::Bool
      (m,pₘ), (n,pₙ) = ob_slice[i], ob_slice[j]
      es = incident(pathₛ, m, :src) ∩ incident(pathₛ, n, :tgt)
      paths = pathₛ[es, :eprops]
      return any(f -> pₘ == vcat(edges.(hom_map(F,f))..., pₙ), paths)
    end

    # Use check_pair to determine pairwise connectivity
    connected = IntDisjointSets(length(ob_slice)) # sym/trans/refl closure
    obs = 1:length(ob_slice)
    for (i,j) in Base.Iterators.product(obs, obs)
      if !in_same_set(connected, i, j) && check_pair(i,j)
        union!(connected, i, j)
      end
    end
    return num_groups(connected) == 1
  end

  # Check for each t ∈ T whether F/t is connected
  return all(connected_nonempty_slice, 1:nv(Gₜ))
end

# Dict utilities
################

# Something like this should be built into Julia, but unfortunately isn't.

"""
Map two given functions across the respective keys and values of a dictionary.
"""
function mappairs(kmap, vmap, pairs::T) where T<:AbstractDict
  (dicttype(T))(kmap(k) => vmap(v) for (k,v) in pairs)
end
mappairs(kmap, vmap, vec::AbstractVector) = map(vmap, vec)


"""
Map a function, which may depend on the key, across the values of a dictionary.
"""
function mapvals(f, pairs::T; keys::Bool=false, iter::Bool=false) where T<:AbstractDict
  (iter ? identity : dicttype(T))(if keys
    (k => f(k,v) for (k,v) in pairs)
  else
    (k => f(v) for (k,v) in pairs)
  end)
end
function mapvals(f, collection; keys::Bool=false, iter::Bool=false)
  do_map = iter ? Iterators.map : map
  if keys
    do_map(f, eachindex(collection), values(collection))
  else
    do_map(f, values(collection))
  end
end

dicttype(::Type{T}) where T <: AbstractDict = T.name.wrapper
dicttype(::Type{<:Iterators.Pairs}) = Dict

@inline make_map(f, xs) = make_map(f, xs, Any)

"""
If `xs` is a UnitRange, make a vector of the desired
type by mapping `f` over `xs`. Otherwise, make a dictionary
with the desired valtype.

Seems like this wants to guarantee the output has type T,
but the Any methods violate this.
"""
make_map(f, xs::UnitRange{Int}, ::Type{Any}) = map(f, xs)
make_map(f, xs, ::Type{Any}) = Dict(x => f(x) for x in xs)

function make_map(f, xs::UnitRange{Int}, ::Type{T}) where T
  if isempty(xs)
    T[]
  else
    ys = map(f, xs)
    eltype(ys) <: T || error("Element(s) of $ys are not instances of $T")
    T[y for y in ys]
  end
end

function make_map(f, xs, ::Type{T}) where T
  if isempty(xs)
    Dict{eltype(xs),T}()
  else
    xys = Dict(x => f(x) for x in xs)
    valtype(xys) <: T || error("Value(s) of $xys are not instances of $T")
    Dict{keytype(xys),T}(x=>y for (x,y) in xys)
  end
end

end
