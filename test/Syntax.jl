""" Test the Syntax module.

The unit tests are sparse because many of the Doctrine tests are really just
tests of the Syntax module.
"""
module TestSyntax

using Base.Test
using CompCat.GAT
using CompCat.Syntax

# Simple case: Monoid (no dependent types)

""" Signature of the theory of monoids.
"""
@signature Monoid(Elem) begin
  Elem::TYPE
  munit()::Elem
  mtimes(x::Elem,y::Elem)::Elem
end

""" Syntax for the theory of monoids.
"""
@syntax FreeMonoid Monoid

@test isa(FreeMonoid, Module)
@test contains(string(Docs.doc(FreeMonoid)), "theory of monoids")
@test sort(names(FreeMonoid)) == sort([:FreeMonoid, :Elem])

S = FreeMonoid
x, y, z = elem(S.Elem,:x), elem(S.Elem,:y), elem(S.Elem,:z)
@test x == elem(S.Elem,:x)
@test x != y
@test elem(S.Elem,"X") == elem(S.Elem,"X")
@test elem(S.Elem,"X") != elem(S.Elem,"Y")

@test isa(mtimes(x,y), S.Elem)
@test isa(munit(S.Elem), S.Elem)
@test mtimes(mtimes(x,y),z) != mtimes(x,mtimes(y,z))

@syntax FreeMonoidAssoc Monoid begin
  mtimes(x::Elem, y::Elem) = associate(Super.mtimes(x,y))
end

S = FreeMonoidAssoc
x, y, z = elem(S.Elem,:x), elem(S.Elem,:y), elem(S.Elem,:z)
e = munit(S.Elem)
@test mtimes(mtimes(x,y),z) == mtimes(x,mtimes(y,z))
@test mtimes(e,x) != x && mtimes(x,e) != x

@syntax FreeMonoidAssocUnit Monoid begin
  mtimes(x::Elem, y::Elem) = associate_unit(Super.mtimes(x,y), munit)
end

S = FreeMonoidAssocUnit
x, y, z = elem(S.Elem,:x), elem(S.Elem,:y), elem(S.Elem,:z)
e = munit(S.Elem)
@test mtimes(mtimes(x,y),z) == mtimes(x,mtimes(y,z))
@test mtimes(e,x) == x && mtimes(x,e) == x

abstract MonoidExpr{T} <: BaseExpr{T}
@syntax FreeMonoidTyped(MonoidExpr) Monoid

x = elem(FreeMonoidTyped.Elem, :x)
@test issubtype(FreeMonoidTyped.Elem, MonoidExpr)
@test isa(x, FreeMonoidTyped.Elem) && isa(x, MonoidExpr)

# Category (includes dependent types)

@signature Category(Ob,Hom) begin
  Ob::TYPE
  Hom(dom::Ob, codom::Ob)::TYPE
  
  id(X::Ob)::Hom(X,X)
  compose(f::Hom(X,Y), g::Hom(Y,Z))::Hom(X,Z) <= (X::Ob, Y::Ob, Z::Ob)
  
  compose(fs::Vararg{Hom}) = foldl(compose, fs)
end

@syntax FreeCategory Category begin
  compose(f::Hom, g::Hom) = associate(Super.compose(f,g))
end

@test isa(FreeCategory, Module)
@test sort(names(FreeCategory)) == sort([:FreeCategory, :Ob, :Hom])

X, Y, Z, W = [ ob(FreeCategory.Ob, sym) for sym in [:X, :Y, :Z, :W] ]
f, g, h = hom(:f, X, Y), hom(:g, Y, Z), hom(:h, Z, W)
@test isa(X, FreeCategory.Ob) && isa(f, FreeCategory.Hom)
@test_throws MethodError FreeCategory.hom(:f)
@test dom(f) == X
@test codom(f) == Y

@test isa(id(X), FreeCategory.Hom)
@test dom(id(X)) == X
@test codom(id(X)) == X

@test isa(compose(f,g), FreeCategory.Hom)
@test dom(compose(f,g)) == X
@test codom(compose(f,g)) == Z
@test isa(compose(f,f), FreeCategory.Hom) # Doesn't check domains.

@test compose(compose(f,g),h) == compose(f,compose(g,h))
@test compose(f,g,h) == compose(compose(f,g),h)
@test dom(compose(f,g,h)) == X
@test codom(compose(f,g,h)) == W

@syntax FreeCategoryStrict Category begin
  compose(f::Hom, g::Hom) = associate(Super.compose(f,g; strict=true))
end

X, Y = ob(FreeCategoryStrict.Ob, :X), ob(FreeCategoryStrict.Ob, :Y)
f, g = hom(:f, X, Y), hom(:g, Y, X)

@test isa(compose(f,g,f), FreeCategoryStrict.Hom)
@test_throws SyntaxDomainError compose(f,f)

@signature Monoid(Elem) => MonoidNumeric(Elem) begin
  elem_int(x::Int)::Elem
end
@syntax FreeMonoidNumeric MonoidNumeric

x = elem_int(FreeMonoidNumeric.Elem, 1)
@test isa(x, FreeMonoidNumeric.Elem)
@test first(x) == 1

end
