
import macros

macro class*(head, body: untyped): untyped =
  # The macro is immediate, since all its parameters are untyped.
  # This means, it doesn't resolve identifiers passed to it.

  var typeName, baseName: NimNode

  # flag if object should be exported
  var exported: bool

  if head.kind == nnkInfix and head[0].ident == !"of":
    # `head` is expression `typeName of baseClass`
    # echo head.treeRepr
    # --------------------
    # Infix
    #   Ident !"of"
    #   Ident !"Animal"
    #   Ident !"RootObj"
    typeName = head[1]
    baseName = head[2]

  elif head.kind == nnkInfix and head[0].ident == !"*" and
       head[2].kind == nnkPrefix and head[2][0].ident == !"of":
    # `head` is expression `typeName* of baseClass`
    # echo head.treeRepr
    # --------------------
    # Infix
    #   Ident !"*"
    #   Ident !"Animal"
    #   Prefix
    #     Ident !"of"
    #     Ident !"RootObj"
    typeName = head[1]
    baseName = head[2][1]
    exported = true

  else:
    quit "Invalid node: " & head.lispRepr

  # The following prints out the AST structure:
  #
  # import macros
  # dumptree:
  #   type X = ref object of Y
  #     z: int
  # --------------------
  # StmtList
  #   TypeSection
  #     TypeDef
  #       Ident !"X"
  #       Empty
  #       RefTy
  #         ObjectTy
  #           Empty
  #           OfInherit
  #             Ident !"Y"
  #           RecList
  #             IdentDefs
  #               Ident !"z"
  #               Ident !"int"
  #               Empty

  # create a type section in the result
  result =
    if exported:
      # mark `typeName` with an asterisk
      quote do:
        type `typeName`* = ref object of `baseName`
    else:
      quote do:
        type `typeName` = ref object of `baseName`

  # echo treeRepr(body)
  # --------------------
  # StmtList
  #   VarSection
  #     IdentDefs
  #       Ident !"name"
  #       Ident !"string"
  #       Empty
  #     IdentDefs
  #       Ident !"age"
  #       Ident !"int"
  #       Empty
  #   MethodDef
  #     Ident !"vocalize"
  #     Empty
  #     Empty
  #     FormalParams
  #       Ident !"string"
  #     Empty
  #     Empty
  #     StmtList
  #       StrLit ...
  #   MethodDef
  #     Ident !"age_human_yrs"
  #     Empty
  #     Empty
  #     FormalParams
  #       Ident !"int"
  #     Empty
  #     Empty
  #     StmtList
  #       DotExpr
  #         Ident !"this"
  #         Ident !"age"

  # var declarations will be turned into object fields
  var recList = newNimNode(nnkRecList)

  # expected name of constructor
  let ctorName = newIdentNode("new" & $typeName)

  # Iterate over the statements, adding `this: T`
  # to the parameters of functions, unless the
  # function is a constructor
  for node in body.children:
    case node.kind:

      of nnkMethodDef, nnkProcDef:
        # check if it is the ctor proc
        if node.name.kind != nnkAccQuoted and node.name.basename == ctorName:
          # specify the return type of the ctor proc
          node.params[0] = typeName
        else:
          # inject `self: T` into the arguments
          node.params.insert(1, newIdentDefs(ident("self"), typeName))
        result.add(node)

      of nnkVarSection:
        # variables get turned into fields of the type.
        for n in node.children:
          recList.add(n)

      else:
        result.add(node)

  # Inspect the tree structure:
  #
  # echo result.treeRepr
  # --------------------
  # StmtList
  #   TypeSection
  #     TypeDef
  #       Ident !"Animal"
  #       Empty
  #       RefTy
  #         ObjectTy
  #           Empty
  #           OfInherit
  #             Ident !"RootObj"
  #           Empty   <= We want to replace this
  # MethodDef
  # ...

  result[0][0][2][0][2] = recList

  # Lets inspect the human-readable version of the output
  #echo repr(result)

# ---

class Animal of RootObj:
  var name: string
  var age: int
  method vocalize: string {.base.} = "..." # use `base` pragma to annonate base methods
  method age_human_yrs: int {.base.} = self.age # `this` is injected
  proc `$`: string = "animal:" & self.name & ":" & $self.age

class Dog of Animal:
  method vocalize: string = "woof"
  method age_human_yrs: int = self.age * 7
  proc `$`: string = "dog:" & self.name & ":" & $self.age

class Cat of Animal:
  method vocalize: string = "meow"
  proc `$`: string = "cat:" & self.name & ":" & $self.age

class Rabbit of Animal:
  proc newRabbit(name: string, age: int) = # the constructor doesn't need a return type
    result = Rabbit(name: name, age: age)
  method vocalize: string = "meep"
  proc `$`: string =
    self.#[!]#
    result = "rabbit:" & self.name & ":" & $self.age

# ---

var animals: seq[Animal] = @[]
animals.add(Dog(name: "Sparky", age: 10))
animals.add(Cat(name: "Mitten", age: 10))

for a in animals:
  echo a.vocalize()
  echo a.age_human_yrs()

let r = newRabbit("Fluffy", 3)
echo r.vocalize()
echo r.age_human_yrs()
echo r

discard """
disabled:true
$nimsuggest --tester $file
>sug $1
sug;;skField;;age;;int;;$file;;167;;6;;"";;100;;None
sug;;skField;;name;;string;;$file;;166;;6;;"";;100;;None
sug;;skMethod;;twithin_macro.age_human_yrs;;proc (self: Animal): int;;$file;;169;;9;;"";;100;;None
sug;;skMethod;;twithin_macro.vocalize;;proc (self: Animal): string;;$file;;168;;9;;"";;100;;None
sug;;skMethod;;twithin_macro.vocalize;;proc (self: Rabbit): string;;$file;;184;;9;;"";;100;;None
sug;;skMacro;;twithin_macro.class;;proc (head: untyped, body: untyped): untyped{.gcsafe, locks: <unknown>.};;$file;;4;;6;;"";;50;;None*
"""
