# Definition of the Decapodes DSL AST
# TODO: do functions and tans need to be parameterized by a space?
# TODO: Add support for higher order functions.
#   - This is straightforward from a language perspective but unclear the best
#   - way to represent this in a Decapode ACSet.
@data Term begin
  Var(Symbol)
  Judge(Var, Symbol, Symbol) # Symbol 1: Form0 Symbol 2: X
  AppCirc1(Vector{Symbol}, Term)
  AppCirc2(Vector{Symbol}, Term, Term)
  App1(Symbol, Term)
  App2(Symbol, Term, Term)
  Plus(Term, Term)
  Tan(Term)
end

@data Equation begin
  Eq(Term, Term)
end

# A struct to store a complete Decapode
# TODO: Have the decopode macro compile to a DecaExpr
struct DecaExpr
  judgements::Vector{Judge}
  equations::Vector{Equation}
end

term(s::Symbol) = Var(normalize_unicode(s))

term(expr::Expr) = begin
    @match expr begin
        Expr(a) => Var(normalize_unicode(a))
        Expr(:call, :∂ₜ, b) => Tan(term(b))
        Expr(:call, Expr(:call, :∘, a...), b) => AppCirc1(a, Var(b))
        Expr(:call, a, b) => App1(a, term(b))
        Expr(:call, Expr(:call, :∘, f...), x, y) => AppCirc1(f, Var(x), Var(y))
        Expr(:call, f, x, y) => App2(f, term(x), term(y))
        Expr(:call, :∘, a...) => (:AppCirc1, map(term, a))
        x => error("Cannot construct term from  $x")
    end
end

function parse_decapode(expr::Expr)
    stmts = map(expr.args) do line 
        @match line begin
            ::LineNumberNode => missing
            Expr(:(::), a, b) => Judge(Var(a),b.args[1], b.args[2])
            Expr(:call, :(==), lhs, rhs) => Eq(term(lhs), term(rhs))
            x => x
        end
    end |> skipmissing |> collect
    judges = []
    eqns = []
    for s in stmts
        if typeof(s) == Judge
            push!(judges, s)
        elseif typeof(s) == Eq
            push!(eqns, s)
        end
    end
    DecaExpr(judges, eqns)
end

# to_decapode helper functions
reduce_term!(t::Term, d::AbstractDecapode, syms::Dict{Symbol, Int}) =
  let ! = reduce_term!
    @match t begin
      Var(x) => syms[x]
      App1(f, t) => begin
        res_var = add_part!(d, :Var, type=:infer)
        add_part!(d, :Op1, src=!(t,d,syms), tgt=res_var, op1=f)
        return res_var
      end
      App2(f, t1, t2) => begin
        res_var = add_part!(d, :Var, type=:infer)
        add_part!(d, :Op2, proj1=!(t1,d,syms), proj2=!(t2,d,syms), res=res_var, op2=f)
        return res_var
      end
      AppCirc1(fs, t) => begin
        res_var = add_part!(d, :Var, type=:infer)
        add_part!(d, :Op1, src=!(t,d,syms), tgt=res_var, op1=fs)
        return res_var
      end
      AppCirc2(f, t1, t2) => begin
        res_var = add_part!(d, :Var, type=:infer)
        add_part!(d, :Op2, proj1=!(t1,d,syms), proj2=!(t2,d,syms), res=res_var, op2=fs)
        return res_var
      end
      Plus(t1, t2) => begin # TODO: plus is an Op2 so just fold it into App2
        res_var = add_part!(d, :Var, type=:infer)
        add_part!(d, :Op2, proj1=!(t1,d,syms), proj2=!(t2,d,syms), res=res_var, op2=:plus)
        return res_var
      end
      Tan(t) => begin 
        # TODO: this is creating a spurious variablbe with the same name
        txv = add_part!(d, :Var, type=:infer)
        tx = add_part!(d, :TVar, incl=txv)
        tanop = add_part!(d, :Op1, src=!(t,d,syms), tgt=txv, op1=DerivOp)
        return txv #syms[x._1]
      end
      _ => throw("Inline type judgements not yet supported!")
    end
  end

function eval_eq!(eq::Equation, d::AbstractDecapode, syms::Dict{Symbol, Int}) 
  @match eq begin
    Eq(t1, t2) => begin
      lhs_ref = reduce_term!(t1,d,syms)
      rhs_ref = reduce_term!(t2,d,syms)
      deletions = []
      # Make rhs_ref equal to lhs_ref and adjust all its incidents
      # Case rhs_ref is a Op1
      for rhs in incident(d, rhs_ref, :tgt)
        d[rhs, :tgt] = lhs_ref
        push!(deletions, rhs_ref)
      end
      # Case rhs_ref is a Op2
      for rhs in incident(d, rhs_ref, :res)
        d[rhs, :res] = lhs_ref
        push!(deletions, rhs_ref)
      end
      # TODO: delete unused vars. The only thing stopping me from doing 
      # this is I don't know if CSet deletion preserves incident relations
      rem_parts!(d, :Var, sort(deletions))
    end
  end
  return d
end

""" Takes a DecaExpr (i.e. what should be constructed using the @decapode macro)
and gives a Decapode ACSet which represents equalities as two operations with the
same tgt or res map.
"""
# Just to get up and running, I tagged untyped variables with :infer
# TODO: write a type checking/inference step for this function to 
# overwrite the :infer tags
function Decapode(e::DecaExpr)
  d = Decapode{Any, Any}()
  symbol_table = Dict{Symbol, Int}()
  for judgement in e.judgements
    var_id = add_part!(d, :Var, type=(judgement._2, judgement._3))
    symbol_table[judgement._1._1] = var_id
  end
  for eq in e.equations
    eval_eq!(eq, d, symbol_table)
  end
  return d
end

function NamedDecapode(e::DecaExpr)
    d = NamedDecapode{Any, Any, Symbol}()
    symbol_table = Dict{Symbol, Int}()
    for judgement in e.judgements
      var_id = add_part!(d, :Var, name=judgement._1._1, type=judgement._2)
      symbol_table[judgement._1._1] = var_id
    end
    for eq in e.equations
      eval_eq!(eq, d, symbol_table)
    end
    fill_names!(d)
    d[:name] = map(normalize_unicode,d[:name])
    return d
end