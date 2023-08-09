@syntax CategoryExprs{ObExpr, HomExpr} ThCategory begin
end

A, B, C, D = [ Ob(CategoryExprs.Ob, X) for X in [:A, :B, :C, :D] ]
f, g, h = Hom(:f, A, B), Hom(:g, B, C), Hom(:h, C, D)

println(compose(compose(f,g),h))