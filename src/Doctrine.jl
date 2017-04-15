module Doctrine
import ..Syntax: BaseExpr

export CategoryExpr, ObExpr, HomExpr, Hom2Expr

# TODO: Generate these automatically from signature?
export Category, FreeCategory, ob, hom, dom, codom, id, compose, ∘
export Category2, FreeCategory2, hom2, compose2

export MonoidalCategory, otimes, munit, ⊗
export SymmetricMonoidalCategory, FreeSymmetricMonoidalCategory, braid
export CartesianCategory, FreeCartesianCategory, mcopy, delete,
  pair, proj1, proj2, Δ, ◇
export CocartesianCategory, FreeCocartesianCategory, mmerge, create,
  copair, in1, in2, ∇, □
export BiproductCategory, FreeBiproductCategory
export CompactClosedCategory, FreeCompactClosedCategory, dual, ev, coev
export DaggerCategory, FreeDaggerCategory, dagger
export DaggerCompactCategory, FreeDaggerCompactCategory

export BicategoryRelations, FreeBicategoryRelations
export AbelianBicategoryRelations, FreeAbelianBicategoryRelations,
  plus, coplus, zero, cozero

abstract CategoryExpr{T} <: BaseExpr{T}
abstract ObExpr{T} <: CategoryExpr{T}
abstract HomExpr{T} <: CategoryExpr{T}
abstract Hom2Expr{T} <: CategoryExpr{T}

# Convenience method: generate this automatically?
ob(mod::Module, args...) = ob(mod.Ob, args...)

include("doctrine/Category.jl")
include("doctrine/Monoidal.jl")
include("doctrine/Relations.jl")

end
