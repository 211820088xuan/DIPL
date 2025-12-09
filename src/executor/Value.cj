package cjcj.executor

import cjcj.visitor.*
import std.deriving.Derive
import std.collection.*



public class RuntimeParam {
    public let name: String
    public let decltype: ?TypeNode

    public init(name: String, decltype: ?TypeNode) {
        this.name = name
        this.decltype = decltype
    }

    public func toString(): String {
        match (decltype) {
            case Some(t) => return "${name}: <type>"
            case None => return name
        }
    }
}


// 用户自定义函数（闭包）
public class UserFunction  {
    public let name: String
    public let params: ArrayList<RuntimeParam>
    // 返回类型、参数类型
    public let returnType: ?TypeNode

    // 函数体 AST（你 visitor 里有 Block、Body 一类的节点，这里用 Block 假设）
    public let body: Block

    public let capturedScopes: ArrayList<HashMap<String, VarInfo>>

    // 在父作用域中的“定义顺序”，后面做“忽略之后定义的变量”用
    public let defOrderInParent: Int64

    public init(
        name: String,
        params: ArrayList<RuntimeParam>,
        returnType: ?TypeNode,
        body: Block,
        capturedScopes: ArrayList<HashMap<String, VarInfo>>,
        defOrderInParent: Int64
    ) {
        this.name = name
        this.params = params
        this.returnType = returnType
        this.body = body
        this.capturedScopes = capturedScopes
        this.defOrderInParent = defOrderInParent
    }

    public func toString(): String {
        return "<User-defined function ${name}>"
    }
}

// 内置函数（println 等）
public class BuiltinFunction {
    public let name: String
    public let paramCount: Int64
    // 仓颉里可以用函数类型 (ArrayList<Value>) -> Value

    public init(name: String, paramCount: Int64) {
        this.name = name
        this.paramCount = paramCount
    }

    public func toString(): String {
        return "<Built-in function ${name}>"
    }
}

// This is a very simple representation of values in the interpreter.
// You may need to extend or modify it depending on your design.
// Depending on your design, you may even need to repackage it with another class.
// @Derive[ToString]
public enum Value {
    | VInteger(Int64)
    | VString(String)
    | VBoolean(Bool)
    | VUnit
    | VFunction(UserFunction)          // 新增：用户函数
    | VBuiltinFunction(BuiltinFunction) // 新增：内置函数


    public func toValueString(): String {
        match (this) {
            case VInteger(i) => return i.toString()
            case VString(s) => return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
            case VBoolean(b) => return b.toString()
            case VUnit => return "()"
             // 对函数值的字符串形式：只要在尖括号里包含 "Function" / "function" 字样即可
            case VFunction(f) =>
                // 打印函数名和参数大致形状，方便调试
                return f.toString()
            case VBuiltinFunction(bf) =>
                return bf.toString()
        }
    }

    static func from(v: Int64): Value {
        VInteger(v)
    }
    static func from(v: String): Value {
        VString(v)
    }
    static func from(v: Bool): Value {
        VBoolean(v)
    }
    static func from(_: Unit): Value {
        VUnit
    }
}

