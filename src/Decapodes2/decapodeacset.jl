@present SchDecapode(FreeSchema) begin
    (Var, TVar, Op1, Op2)::Ob
    (Type, Operator)::AttrType
    src::Hom(Op1, Var)
    tgt::Hom(Op1, Var)
    proj1::Hom(Op2, Var)
    proj2::Hom(Op2, Var)
    res::Hom(Op2, Var)
    incl::Hom(TVar, Var)
    
    op1::Attr(Op1, Operator)
    op2::Attr(Op2, Operator)
    type::Attr(Var, Type)
end

@present SchNamedDecapode <: SchDecapode begin
    Name::AttrType
    name::Attr(Var, Name)
end

@abstract_acset_type AbstractDecapode

@acset_type Decapode(SchDecapode,
  index=[:src, :tgt, :res, :incl, :op1, :op2, :type]) <: AbstractDecapode

@acset_type NamedDecapode(SchNamedDecapode,
  index=[:src, :tgt, :res, :incl, :op1, :op2, :type, :name]) <: AbstractDecapode

"""    fill_names!

add new variable names to all the variables that don't have names.
"""
function fill_names!(d::NamedDecapode)
    bulletcount = 1
    for i in parts(d, :Var)
        if !isassigned(d[:,:name],i)
            d[i,:name] = Symbol("•$bulletcount")
            bulletcount += 1
        end
    end
    for e in incident(d, :∂ₜ, :op1)
        s = d[e,:src]
        t = d[e, :tgt]
        d[t, :name] = append_dot(d[s,:name])
    end
    return d
end

function expand_operators(d::NamedDecapode)
  e = NamedDecapode{Symbol, Symbol, Symbol}()
  copy_parts!(e, d, (:Var, :TVar, :Op2))
  newvar = 0
  for op in parts(d, :Op1)
    if !isa(d[op,:op1], AbstractArray)
      add_part!(e, :Op1, op1=d[op,:op1], src=d[op, :src], tgt=d[op,:tgt])
    else
      for (i, step) in enumerate(d[op, :op1])
        if i == 1
          newvar = add_part!(e, :Var, type=:infer, name=Symbol("•_$(op)_$(i)"))
          add_part!(e, :Op1, op1=step, src=d[op, :src], tgt=newvar)
        elseif i == length(d[op, :op1])
          add_part!(e, :Op1, op1=step, src=newvar, tgt=d[op,:tgt])
        else
          newvar′ = add_part!(e, :Var, type=:infer, name=Symbol("•_$(op)_$(i)"))
          add_part!(e, :Op1, op1=step, src=newvar, tgt=newvar′)
          newvar = newvar′
        end
      end
    end
  end
  return e
end
