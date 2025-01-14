module TestHomSearch 

using Test
using Catlab
using Random: seed!

# Setup
#######

seed!(100)

@present SchSetAttr(FreeSchema) begin
  X::Ob
  D::AttrType
  f::Attr(X,D)
end
@acset_type SetAttr(SchSetAttr)

# Finding C-set morphisms
#########################

# Graphs
#-------

g, h = path_graph(Graph, 3), path_graph(Graph, 4)
homs = [ACSetTransformation((V=[1,2,3], E=[1,2]), g, h),
        ACSetTransformation((V=[2,3,4], E=[2,3]), g, h)]
@test homomorphisms(g, h) == homs
@test homomorphisms(g, h, alg=HomomorphismQuery()) == homs
@test !is_isomorphic(g, h)

I = ob(terminal(Graph))
α = ACSetTransformation((V=[1,1,1], E=[1,1]), g, I)
@test homomorphism(g, I) == α
@test homomorphism(g, I, alg=HomomorphismQuery()) == α
@test !is_homomorphic(g, I, monic=true)
@test !is_homomorphic(I, h)
@test !is_homomorphic(I, h, alg=HomomorphismQuery())

# Graph homomorphism starting from partial assignment, e.g. vertex assignment.
α = ACSetTransformation((V=[2,3,4], E=[2,3]), g, h)
@test homomorphisms(g, h, initial=(V=[2,3,4],)) == [α]
@test homomorphisms(g, h, initial=(V=Dict(1 => 2, 3 => 4),)) == [α]
@test homomorphisms(g, h, initial=(E=Dict(1 => 2),)) == [α]
# Inconsistent initial assignment.
@test !is_homomorphic(g, h, initial=(V=Dict(1 => 1), E=Dict(1 => 3)))
# Consistent initial assignment but no extension to complete assignment.
@test !is_homomorphic(g, h, initial=(V=Dict(1 => 2, 3 => 3),))

# Monic and iso on a componentwise basis.
g1, g2 = path_graph(Graph, 3), path_graph(Graph, 2)
add_edges!(g1, [1,2,3,2], [1,2,3,3])  # loops on each node and one double arrow
add_edge!(g2, 1, 2)  # double arrow
@test length(homomorphisms(g2, g1)) == 8 # each vertex + 1->2, and four for 2->3
@test length(homomorphisms(g2, g1, monic=[:V])) == 5 # remove vertex solutions
@test length(homomorphisms(g2, g1, monic=[:E])) == 2 # two for 2->3
@test length(homomorphisms(g2, g1, iso=[:E])) == 0

# Loose
s1 = SetAttr{Int}()
add_part!(s1, :X, f=1)
add_part!(s1, :X, f=1)
s2, s3 = deepcopy(s1), deepcopy(s1)
set_subpart!(s2, :f, [2,1])
set_subpart!(s3, :f, [20,10])
@test length(homomorphisms(s2,s3))==0
@test length(homomorphisms(s2,s3; type_components=(D=x->10*x,)))==1
@test homomorphism(s2,s3; type_components=(D=x->10*x,)) isa LooseACSetTransformation
@test length(homomorphisms(s1,s1; type_components=(D=x->x^x,)))==4

#Backtracking with monic and iso failure objects
g1, g2 = path_graph(Graph, 3), path_graph(Graph, 2)
rem_part!(g1,:E,2)
@test_throws ErrorException homomorphism(g1,g2;monic=true,error_failures=true)

# Symmetric graphs
#-----------------

g, h = path_graph(SymmetricGraph, 4), path_graph(SymmetricGraph, 4)
αs = homomorphisms(g, h)
@test all(is_natural(α) for α in αs)
@test length(αs) == 16
αs = isomorphisms(g, h)
@test length(αs) == 2
@test map(α -> collect(α[:V]), αs) == [[1,2,3,4], [4,3,2,1]]
g = path_graph(SymmetricGraph, 3)
@test length(homomorphisms(g, h, monic=true)) == 4

# Graph colorability via symmetric graph homomorphism.
# The 5-cycle has chromatic number 3 but the 6-cycle has chromatic number 2.
K₂, K₃ = complete_graph(SymmetricGraph, 2), complete_graph(SymmetricGraph, 3)
C₅, C₆ = cycle_graph(SymmetricGraph, 5), cycle_graph(SymmetricGraph, 6)
@test !is_homomorphic(C₅, K₂)
@test is_homomorphic(C₅, K₃)
@test is_natural(homomorphism(C₅, K₃))
@test is_homomorphic(C₆, K₂)
@test is_natural(homomorphism(C₆, K₂))

# Labeled graphs
#---------------

g = cycle_graph(LabeledGraph{Symbol}, 4, V=(label=[:a,:b,:c,:d],))
h = cycle_graph(LabeledGraph{Symbol}, 4, V=(label=[:c,:d,:a,:b],))
α = ACSetTransformation((V=[3,4,1,2], E=[3,4,1,2]), g, h)
@test homomorphism(g, h) == α
@test homomorphism(g, h, alg=HomomorphismQuery()) == α
h = cycle_graph(LabeledGraph{Symbol}, 4, V=(label=[:a,:b,:d,:c],))
@test !is_homomorphic(g, h)
@test !is_homomorphic(g, h, alg=HomomorphismQuery())

# Random
#-------

comps(x) = sort([k=>collect(v) for (k,v) in pairs(components(x))])
# same set of morphisms
K₆ = complete_graph(SymmetricGraph, 6)
hs = homomorphisms(K₆,K₆)
rand_hs = homomorphisms(K₆,K₆; random=true)
@test sort(hs,by=comps) == sort(rand_hs,by=comps) # equal up to order
@test hs != rand_hs # not equal given order
@test homomorphism(K₆,K₆) != homomorphism(K₆,K₆;random=true)

# As a macro
#-----------

g = cycle_graph(LabeledGraph{String}, 4, V=(label=["a","b","c","d"],))
h = cycle_graph(LabeledGraph{String}, 4, V=(label=["b","c","d","a"],))
α = @acset_transformation g h
β = @acset_transformation g h begin
  V = [4,1,2,3]
  E = [4,1,2,3]
end monic=true
γ = @acset_transformation g h begin end monic=[:V]
@test α[:V](1) == 4
@test α[:E](1) == 4
@test α == β == γ

x = @acset Graph begin
  V = 2
  E = 2
  src = [1,1]
  tgt = [2,2]
end
@test length(@acset_transformations x x) == length(@acset_transformations x x monic=[:V]) == 4
@test length(@acset_transformations x x monic = true) == 2
@test length(@acset_transformations x x begin V=[1,2] end monic = [:E]) == 2
@test length(@acset_transformations x x begin V = Dict(1=>1) end monic = [:E]) == 2
@test_throws ErrorException @acset_transformation g h begin V = [4,3,2,1]; E = [1,2,3,4] end


# Enumeration of subobjects 
###########################

G = path_graph(Graph, 3)
subG, subobjs = subobject_graph(G) |> collect
@test length(subobjs) == 13 # ⊤,2x •→• •,2x •→•, •••,3x ••, 3x •, ⊥
@test length(incident(subG, 13, :src)) == 13 # ⊥ is initial
@test length(incident(subG, 1, :src)) == 1 # ⊤ is terminal

# Graph and ReflexiveGraph should have same subobject structure
subG = subobject_graph(path_graph(Graph, 2)) |> first
subRG, sos = subobject_graph(path_graph(ReflexiveGraph, 2))
@test all(is_natural, hom.(sos))
@test is_isomorphic(subG, subRG)

# Partial overlaps 
G,H = path_graph.(Graph, 2:3)
os = collect(partial_overlaps(G,G))
@test length(os) == 7 # ⊤, ••, 4× •, ⊥

po = partial_overlaps([G,H])
@test length(collect(po))==12  # 2×⊤, 3×••, 6× •, ⊥
@test all(m -> apex(m) == G, Iterators.take(po, 2)) # first two are •→•
@test all(m -> apex(m) == Graph(2), 
          Iterators.take(Iterators.drop(po, 2), 3)) # next three are • •

# Maximum Common C-Set
######################

"""
Searching for overlaps: •→•→•↺  vs ↻•→•→•
Two results: •→•→• || •↺ •→• 
"""
g1 = @acset WeightedGraph{Bool} begin 
  V=3; E=3; src=[1,1,2]; tgt=[1,2,3]; weight=[true,false,false]
end
g2 = @acset WeightedGraph{Bool} begin 
  V=3; E=3; src=[1,2,3]; tgt=[2,3,3]; weight=[true,false,false] 
end
apex1 = @acset WeightedGraph{Bool} begin
  V=3; E=2; Weight=2; src=[1,2]; tgt=[2,3]; weight=AttrVar.(1:2)
end
apex2 = @acset WeightedGraph{Bool} begin 
  V=3; E=2; Weight=2; src=[1,3]; tgt=[2,3]; weight=AttrVar.(1:2)
end

results = collect(maximum_common_subobject(g1, g2))
@test length(results) == 2
is_iso1 = map(result -> is_isomorphic(first(result), apex1), results)
@test sum(is_iso1) == 1
results = first(is_iso1) ? results : reverse(results)
(apx1,((L1,R1),)), (apx2,((L2,R2),)) = results
@test collect(L1[:V]) == [1,2,3]
@test collect(R1[:V]) == [1,2,3]
@test L1(apx1) == Subobject(g1, V=[1,2,3], E=[2,3])

@test is_isomorphic(apx2, apex2)
@test collect(L2[:V]) == [1,2,3]
@test collect(R2[:V]) == [3,1,2]
@test L2(apx2) == Subobject(g1, V=[1,2,3], E=[1,3])

end # module
