package cjcj.executor

import std.collection.*
import cjcj.visitor.*
import cjcj.scanner.TokenKind
import cjcj.scanner.Token
import std.convert.*

public enum StaticType {
    | TInt64
    | TString
    | TBool
    | TUnit
    | TClass(String)                // 类名
    | TOption(StaticType)           // Option<T>
    | TFunc(ArrayList<StaticType>, StaticType) // (t1, t2, ...) -> tret
    | TTuple(ArrayList<StaticType>)            // (t1, t2, ...)
    | TBottom                       // Nothing


    public operator func ==(right: StaticType): Bool {
        match ((this, right)) {
            case (StaticType.TInt64, StaticType.TInt64) => true
            case (StaticType.TString, StaticType.TString) => true
            case (StaticType.TBool, StaticType.TBool) => true
            case (StaticType.TUnit, StaticType.TUnit) => true
            case (StaticType.TBottom, StaticType.TBottom) => true

            case (StaticType.TClass(c1), StaticType.TClass(c2)) =>
                c1 == c2

            case (StaticType.TOption(t1), StaticType.TOption(t2)) =>
                t1 == t2

            case (StaticType.TFunc(p1, r1), StaticType.TFunc(p2, r2)) => 
                if (p1.size != p2.size) {
                    false
                } else {
                    var ok = true
                    for (i in 0..p1.size - 1) {
                        if (!(p1.get(i).getOrThrow() == p2.get(i).getOrThrow())) {
                            ok = false
                            break
                        }
                    }
                    ok && (r1 == r2)
                }
            

            case (StaticType.TTuple(ts1), StaticType.TTuple(ts2)) => 
                if (ts1.size != ts2.size) {
                    false
                } else {
                    var ok = true
                    for (i in 0..ts1.size - 1) {
                        if (!(ts1.get(i).getOrThrow() == ts2.get(i).getOrThrow())) {
                            ok = false
                            break
                        }
                    }
                    ok
                }
            

            case _ => false
        }
    }  

    public static func join(a: StaticType, b: StaticType): Option<StaticType> {
        if (a == b) {
            return Option.Some(a)
        }

        match ((a, b)) {
            case (StaticType.TBottom, x) => Option.Some(x)
            case (x, StaticType.TBottom) => Option.Some(x)
            case _ => Option.None
        }
    }

    public func toString(): String {
        match (this) {
            case StaticType.TInt64 => "Int64"
            case StaticType.TString => "String"
            case StaticType.TBool => "Bool"
            case StaticType.TUnit => "Unit"
            case StaticType.TBottom => "Nothing"
            case StaticType.TClass(name) => name
            case StaticType.TOption(inner) => "Option<${inner.toString()}>"
            case StaticType.TFunc(paramTypes, retType) => 
                var paramStrs = ArrayList<String>()
                for (t in paramTypes.iterator()) {
                    paramStrs.add(t.toString())
                }
                // 手动拼接字符串
                var paramsStr = ""
                var first = true
                for (str in paramStrs.iterator()) {
                    if (!first) {
                        paramsStr = paramsStr + ", "
                    }
                    paramsStr = paramsStr + str
                    first = false
                }
                "(${paramsStr}) -> ${retType.toString()}"
            case StaticType.TTuple(elementTypes) => 
                var elemStrs = ArrayList<String>()
                for (t in elementTypes.iterator()) {
                    elemStrs.add(t.toString())
                }
                // 手动拼接字符串
                var elemsStr = ""
                var first = true
                for (str in elemStrs.iterator()) {
                    if (!first) {
                        elemsStr = elemsStr + ", "
                    }
                    elemsStr = elemsStr + str
                    first = false
                }
                "(${elemsStr})"
                    }
                }
}

public func fromTypeNode(node: TypeNode): StaticType {
    match (node) {
        case t : PrimitiveType => 
            let name = t.typeName.value
            match (name) {
                case "Int64" => StaticType.TInt64
                case "String" => StaticType.TString
                case "Bool" => StaticType.TBool
                case "Unit" => StaticType.TUnit
                case _ => throw Exception("unknown primitive type: " + name)
            }
        
        case t : RefType => 
            // 假定 RefType 有 name, typeArgs 字段
            let name = t.typeName.value
            if (name == "Option") {
                if (t.typeArguments.size != 1) {
                    throw Exception("Option must have exactly one type argument")
                }
                let inner = fromTypeNode(t.typeArguments[0])
                StaticType.TOption(inner)
            } else {
                StaticType.TClass(name)
            }
        
        case t: FuncType => 
            let paramTypes = ArrayList<StaticType>()
            for (p in t.paramTypes.iterator()) {
                paramTypes.add(fromTypeNode(p))
            }
            let retType = fromTypeNode(t.returnType)
            StaticType.TFunc(paramTypes, retType)

        case t: TupleType => 
            let elems = ArrayList<StaticType>()
            for (tt in t.elementTypes.iterator()) {
                elems.add(fromTypeNode(tt))
            }
            StaticType.TTuple(elems)
        
        case _ =>
            throw Exception("unknown type node")
    }
}



public func isSubtype(a: StaticType, b: StaticType): Bool {
    // Nothing 是任何类型的子类型
    match (a) {
        case StaticType.TBottom => true
        case _ => a == b
    }
}
