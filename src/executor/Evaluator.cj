package cjcj.executor
import cjcj.visitor.*
import cjcj.scanner.TokenKind
import cjcj.scanner.Token
import std.convert.*
import std.collection.*
import std.ast.Position as AstPos

class Lab1TodoException <: Exception {
    public init(message: String) {
        super("Lab 1 TODO: " + message)
    }
}



//记录变量信息
public open class VarInfo {
    public let isMutable: Bool
    public let declaredType: ?PrimitiveType
    public var initialized: Bool
    public var value: Value
    public let isGlobal: Bool                 // ★ 新增：是否是全局绑定

    public init(isMut: Bool, declaredType: ?PrimitiveType, initialized: Bool, value: Value,isGlobal: Bool) {
        this.isMutable = isMut
        this.declaredType = declaredType
        this.initialized = initialized
        this.value = value
        this.isGlobal = isGlobal
    }
}

public class BreakSignal <: Exception {}
public class ContinueSignal <: Exception {}

public class ReturnSignal <: Exception {
    public let value: Value

    public init(value: Value) {
        this.value = value
    }
}


/** 
 * Evaluator Visitor
 *
 * We have given the simplest form, each `Node` will return a `Value` after evaluation.
 * But is this sufficient? Do you need to add something new to handle ASTs that don't return a value?
 *
 * You may need to modify the member variables and/or generic parameters of the Evaluator class.
 */
public open class Evaluator <: Visitor<Value> {
    // How do you get and set the context when executing an expression?
    // You might need to add some member variables to do this.
    //
    // private let context = ...
    //作用域栈
    private var scopes = ArrayList<HashMap<String, VarInfo>>();

    ////当前作用域栈
    private var currentFunction: ?UserFunction = None

    //是否在循环中
    private var inLoop = false


    public init() {
        this.scopes = ArrayList<HashMap<String, VarInfo>>() // 全局作用域
        this.scopes.add(HashMap<String, VarInfo>())
        // 在全局作用域注册内置函数 println
        let global = this.scopes[0]
        let builtinPrintln = BuiltinFunction(
            "println",
            1,    
        )

        global["println"] = VarInfo(
            false,              // 不可变
            None,        // 先不写类型（题目说参数 Any 就不用检查类型）
            true,
            Value.VBuiltinFunction(builtinPrintln),
            true             // 标记为全局绑定
        )
    }

     private func pushScope() {
        // 添加新的空作用域
        this.scopes.add(HashMap<String, VarInfo>())
    }

    private func popScope() {
        this.scopes.remove(at : this.scopes.size - 1);
    }

    private func currentScope() : HashMap<String, VarInfo> {
        return this.scopes[this.scopes.size - 1]
    }

    //查找变量作用域
    private func findScope(name: String) : ?HashMap<String, VarInfo>{
        var i = this.scopes.size - 1
        while (i >= 0) {
            let scope = this.scopes[i]
            if (scope.contains(name)) {
                return Some(scope)
            }
            i = i - 1
        }
        return None
    }

    // 在 Evaluator 类里添加（靠近其他私有 helper）
    private func repeatString(s: String, times: Int): String {
        // times >= 0 已由调用方保证；这里再防御性判断
        if (times <= 0) {
            return ""
        }

        // 二分倍增构建法：O(log n) 次拼接，避免每次都重新拷贝
        var result = ""
        var part = s
        var t = times
        while (t > 0) {
            if (t % 2 == 1) {
                result += part
            }
            t = t / 2
            if (t > 0) {
                part += part
            }
        }
        return result
    }


    //获取值的类型名称
    private func valType(v: Value): String {
        match (v) {
            case Value.VInteger(_) => return "Int64"
            case Value.VString(_)  => return "String"
            case Value.VBoolean(_) => return "Bool"
            case Value.VUnit       => return "Unit"
            case Value.VFunction(_) => return "Function"
            case Value.VBuiltinFunction(_) => return "Built-in Function"
        }
    }

    // 供内置 println 使用的打印格式：
    private func formatForBuiltinPrintln(v: Value): String {
        match (v) {
            case Value.VBoolean(b)  => return b.toString()
            case Value.VInteger(i)  => return i.toString()
            case Value.VString(s)   => return s   // ★ 不加引号，不转义
            case Value.VUnit        => return "()"
            case Value.VFunction(_) =>
                return "<Function>"
            case Value.VBuiltinFunction(bf) =>
                return "<Built-in function ${bf.name}>"
        }
    }

    private func callBuiltinPrintln(arg: Value): Value {
        let s = this.formatForBuiltinPrintln(arg)
        println(s)

        return Value.VUnit
    }

    private func copyScopesForClosure(): ArrayList<HashMap<String, VarInfo>> {
            let copied = ArrayList<HashMap<String, VarInfo>>()
            for (scope in this.scopes.iterator()) {
                copied.add(scope)
            }
            return copied
    }



    public open override func visit(prog: Program): Value {
        // 1. 第一遍：注册所有顶层函数（以及之后可能的全局变量）
        var mainDeclOpt: ?MainDecl = None

        for (d in prog.decls.iterator()) {
            match (d) {
                // 顶层函数定义：调用你已经写好的 visit(FuncDecl)
                case f: FuncDecl =>
                    f.traverse(this)
                case _ =>
                    ()
            }
        }

        for (d in prog.decls.iterator()) {
            match (d) {
                // 记录 main，但先不执行
                case m: MainDecl =>
                    mainDeclOpt = Some(m)

                case v: VarDecl =>
                    v.traverse(this)    

                case _ =>
                    ()    
            }
        }
        

        // 2. 必须有 main
        if (mainDeclOpt.isNone()) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.UNDEFINED_VAR,
                "no main function defined",
                prog
            )
        }

        let mainDecl = mainDeclOpt.getOrThrow()
        // 3. 执行 main
        return mainDecl.traverse(this)
    }



    //二元表达式
    public open override func visit(expr: BinaryExpr): Value {
        let left = expr.left.traverse(this)
        let right = expr.right.traverse(this)
        try {
            match (expr.oper.kind) {
                case TokenKind.ADD => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a + b)
                    case (VString(a), VString(b)) => Value.from(a + b)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.ADD_TYPE_MISMATCH,
                        "cannot add left = ${left.toValueString()}, right = ${right.toValueString()}", expr)
                }
                case TokenKind.SUB => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a - b)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.SUB_TYPE_MISMATCH,
                        "cannot subtract ${left.toValueString()} and ${right.toValueString()}", expr)
                }
                case TokenKind.MUL => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a * b)
                    // String * Int
                    case (VString(a), VInteger(b)) =>
                        if (b < 0) {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.MUL_TYPE_MISMATCH,
                                "cannot repeat string '${a}' negative times",
                                expr
                            )
                        }
                        Value.from(repeatString(a, b))
                    // Int * String
                    case (VInteger(a), VString(b)) =>
                        if (a < 0) {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.MUL_TYPE_MISMATCH,
                                "cannot repeat string '${b}' negative times",
                                expr
                            )
                        }
                        Value.from(repeatString(b, a))

                    // Other types not supported
                    case _ =>
                        throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.MUL_TYPE_MISMATCH,
                            "cannot multiply left = ${left.toValueString()}, right = ${right.toValueString()}",
                            expr
                        )
                }
                case TokenKind.DIV => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) =>
                        if (b == 0) {
                            throw CjcjRuntimeErrorWithLocation(ErrorCode.DIV_BY_ZERO, "divide by zero", expr)
                        }
                        Value.from(a / b)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.DIV_TYPE_MISMATCH,
                        "cannot divide ${left.toValueString()} and ${right.toValueString()}", expr)
                }
                case TokenKind.MOD => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) =>
                        if (b == 0) {
                            throw CjcjRuntimeErrorWithLocation(ErrorCode.MOD_BY_ZERO, "modulo by zero", expr)
                        }
                        Value.from(a % b)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.MOD_TYPE_MISMATCH,
                        "cannot modulo ${left.toValueString()} and ${right.toValueString()}", expr)
                }

                //  乘方
                case TokenKind.EXP => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) =>
                        if (b < 0) {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.EXP_NEGATIVE_POWER,
                                "exponentiation with negative exponent: ${b}",
                                expr
                            )
                        }
                        var result: Int64 = 1
                        try {
                            for (i in 0 .. b) {
                                result = result * a
                            }
                        } catch (e: OverflowException) {
                            throw CjcjRuntimeErrorWithLocation(ErrorCode.EXP_OVERFLOW,
                                "exponentiation overflow: base = ${a}, exponent = ${b}", expr)
                        }
                        return Value.from(result)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.EXP_TYPE_MISMATCH,
                        "cannot exponentiate ${left.toValueString()} to the power of ${right.toValueString()}", expr)
                }
                //比较操作
                case TokenKind.LT => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a < b)  // 返回 VBoolean 类型
                    case _ => throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.CMP_TYPE_MISMATCH,
                        "cannot compare left = ${left.toValueString()} with right = ${right.toValueString()}", expr
                    )
                }
                case TokenKind.GT => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a > b)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.CMP_TYPE_MISMATCH,
                        "cannot compare left = ${left.toValueString()} with right = ${right.toValueString()}", expr)
                }

                case TokenKind.LE => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a <= b)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.CMP_TYPE_MISMATCH,
                        "cannot compare left = ${left.toValueString()} with right = ${right.toValueString()}", expr)
                }

                case TokenKind.GE => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a >= b)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.CMP_TYPE_MISMATCH,
                        "cannot compare left = ${left.toValueString()} with right = ${right.toValueString()}", expr)
                }
                case TokenKind.EQUAL => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a == b)
                    case (VBoolean(a), VBoolean(b)) => Value.from(a == b)
                    case (VString(a), VString(b))   => Value.from(a == b)
                    case _ => throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.EQ_TYPE_MISMATCH,
                        "cannot compare left = ${left.toValueString()} with right = ${right.toValueString()}", expr
                    )
                }
                case TokenKind.NOTEQ => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a != b)
                    case (VBoolean(a), VBoolean(b)) => Value.from(a != b)
                    case (VString(a), VString(b))   => Value.from(a != b)
                    case _ => throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.NEQ_TYPE_MISMATCH,
                        "cannot compare left = ${left.toValueString()} with right = ${right.toValueString()}", expr
                    )
                }
                // 逻辑与（短路求值）
                case TokenKind.AND => 
                    // 先计算左操作数
                    let leftValue = expr.left.traverse(this)
                    match (leftValue) {
                        case VBoolean(a) => 
                            if (!a) {
                                // a 为 false，短路，直接返回 false，不计算右边
                                return Value.from(false)
                            } else {
                                // a 为 true，才计算右操作数
                                let rightValue = expr.right.traverse(this)
                                match (rightValue) {
                                    case VBoolean(b) => Value.from(b)
                                    case _ => throw CjcjRuntimeErrorWithLocation(
                                        ErrorCode.AND_TYPE_MISMATCH,
                                        "logical and requires Bool operands but got right = ${rightValue.toValueString()}",
                                        expr
                                    )
                                }
                            }
                        case _ => throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.AND_TYPE_MISMATCH,
                            "logical and requires Bool operands but got left = ${leftValue.toValueString()}",
                            expr
                        )
                    }
                // 逻辑或（短路求值）
                case TokenKind.OR => 
                    let leftValue = expr.left.traverse(this)
                    match (leftValue) {
                        case VBoolean(a) => 
                            if (a) {
                                // a 为 true，短路，直接返回 true
                                return Value.from(true)
                            } else {
                                // a 为 false，才计算右操作数
                                let rightValue = expr.right.traverse(this)
                                match (rightValue) {
                                    case VBoolean(b) => Value.from(b)
                                    case _ => throw CjcjRuntimeErrorWithLocation(
                                        ErrorCode.OR_TYPE_MISMATCH,
                                        "logical or requires Bool operands but got right = ${rightValue.toValueString()}",
                                        expr
                                    )
                                }
                            }
                        case _ => throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.OR_TYPE_MISMATCH,
                            "logical or requires Bool operands but got left = ${leftValue.toValueString()}",
                            expr
                        )
                    }
                
                case _ => throw Lab1TodoException("Unimplemented Binary Operator `${expr.oper.kind}`")
            }
        } catch (e: OverflowException) {
            match (e.message) {
                case "add" => throw CjcjRuntimeErrorWithLocation(ErrorCode.ADD_OVERFLOW,
                    "overflow add: left = ${left.toValueString()}, right = ${right.toValueString()}", expr)
                case _ => throw Lab1TodoException("You need to handle overflow of ${e.message}")
            }
        }
    }

    //一元表达式
    public open override func visit(expr: UnaryExpr): Value {
        let v = expr.right.traverse(this)

        match (expr.oper.kind) {
            // 数值取负
            case TokenKind.SUB => match (v) {
                case VInteger(n) => 
                    try {
                        return Value.from(-n)
                    } catch (e: OverflowException) {
                        throw CjcjRuntimeErrorWithLocation(ErrorCode.NEG_OVERFLOW,
                            "negation overflow: ${v.toValueString()}", expr)
                    }
                case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.NEG_TYPE_MISMATCH,
                    "negation requires Int64 but got ${v.toValueString()}", expr)
            }

            // 逻辑非
            case TokenKind.NOT => match (v) {
                case VBoolean(b) => return Value.from(!b)
                case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.NOT_TYPE_MISMATCH,
                    "logical not requires Bool but got ${v.toValueString()}", expr)
            }

            // 其他暂不支持
            case _ => throw Lab1TodoException("Unsupported unary operator: ${expr.oper.kind}")
        }
    }

    //括号表达式
    public open override func visit(par: ParenExpr): Value {
        // 直接求括号内的表达式值
        return par.parenthesizedExpr.traverse(this)
    }


    //字面量表达式
    public open override func visit(lit: LitConstExpr): Value {
        match (lit.literal.kind) {
            case TokenKind.INTEGER_LITERAL => 
                // 整数字面量
                return Value.from(Int.parse(lit.literal.value))

            case TokenKind.STRING_LITERAL => 
                // 仓颉的字符串字面量支持双引号包裹，这里直接取出内容
                return Value.from(lit.literal.value)

            case TokenKind.BOOL_LITERAL =>
                // 布尔字面量 true/false
                match (lit.literal.value) {
                    case "true"  => return Value.from(true)
                    case "false" => return Value.from(false)
                    case _ => throw Lab1TodoException("Invalid boolean literal: ${lit.literal.value}")
            }

            case TokenKind.UNIT_LITERAL =>
                return Value.VUnit

            case _ =>
                throw Lab1TodoException("Unsupported literal type: ${lit.literal.kind}")
        }
    }

    //  赋值表达式
    public open override func visit(expr: AssignExpr): Value {
        // 获取变量名
        let refExp = expr.left
        // 左侧必须是变量引用（RefExpr），从 identifier 取名字
        match (refExp) {
            case ref: RefExpr =>
                let name = ref.identifier.value

                // 查找变量所在作用域
                let optScope = this.findScope(name)
                if (optScope.isNone()) {
                    throw CjcjRuntimeErrorWithLocation(ErrorCode.UNDEFINED_VAR,
                        "undefined variable '${name}'", expr)
                }

                // 解包作用域映射，获取变量信息
                let scope = optScope.getOrThrow()
                let info = scope.get(name).getOrThrow()
                // 计算右值
                let rval = expr.right.traverse(this)

                // 可变变量（var）：检查类型一致性
                if (info.initialized) {
                    if (this.valType(info.value) != this.valType(rval)) {
                        throw CjcjRuntimeErrorWithLocation(ErrorCode.ASSIGN_TYPE_MISMATCH,
                            "type mismatch on assign to '${name}'", expr)
                    }
                } else {
                    // 如果变量未初始化，标记为已初始化
                    info.initialized = true
                }

                // 赋值操作
                if (info.isMutable) {
                    info.value = rval
                } else {
                    throw CjcjRuntimeErrorWithLocation(ErrorCode.ASSIGN_IMMUT_VAR,
                        "cannot modify immutable variable '${name}'", expr)
                }

                scope[name] = info
                return Value.VUnit

            case _ =>
                throw Lab1TodoException("Unsupported left-hand side in assignment")
        }

        return Value.VUnit
    }

    //变量引用表达式
    public open override func visit(ref: RefExpr): Value {
        let name = ref.identifier.value;

        // 手动搜索 scope，同时记录 index
        var idx = this.scopes.size - 1
        var foundScope: ?HashMap<String, VarInfo> = None
        var foundIndex: Int64 = -1

        while (idx >= 0) {
            let scope = this.scopes[idx]
            if (scope.contains(name)) {
                foundScope = Some(scope)
                foundIndex = idx
                break
            }
            idx = idx - 1
        }

        if (foundScope.isNone()) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.UNDEFINED_VAR,
                "undefined variable '${name}'",
                ref
            )
        }

        let scope = foundScope.getOrThrow()
        let info = scope.get(name).getOrThrow()

        if (!info.initialized) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.UNINITIALIZED_VAR,
                "variable '${name}' used before initialization",
                ref
            )
        }

        if (this.currentFunction.isSome()) {
            let fn = this.currentFunction.getOrThrow()
            let capturedCount = fn.capturedScopes.size

            if (foundIndex < capturedCount && !info.isGlobal) {
                if (info.isMutable) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.FUNC_USE_MUTABLE_NONLOCAL,
                        "cannot use mutable nonlocal variable '${name}' inside function '${fn.name}'",
                        ref
                    )
                }
            }
        }

        return info.value
    }

    public open override func visit(block: Block): Value {
        pushScope()
        var ret = Value.VUnit
        for (stmt in block.nodes.iterator()) {
            ret = stmt.traverse(this)
        }
        popScope()
        return ret
    }

    public open override func visit(expr: IfExpr): Value {
        let cond = expr.condition.traverse(this)
        match (cond) {
            case VBoolean(b) =>
                if (b) {
                    pushScope()
                    var result = expr.ifBlock.traverse(this)
                    popScope()
                    return result
                } else {
                    pushScope()
                    var result = expr.elseBranch.traverse(this)
                    popScope()
                    return result
                }
            case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.IF_TYPE_MISMATCH,
                "if condition must be Bool", expr)
        }
    }

    public open override func visit(expr: WhileExpr): Value {
        inLoop = true
        while (inLoop) {
        // 求条件
        let condValue = expr.condition.traverse(this)

        // 检查是否为 Bool
        match (condValue) {
            case Value.VBoolean(flag) =>
                if (!flag) {
                    break
                }
            case _ =>
                throw CjcjRuntimeErrorWithLocation(
                    ErrorCode.WHILE_TYPE_MISMATCH,
                    "While loop condition must be Bool, got ${this.valType(condValue)}",
                    expr
                )
        }
        pushScope()
        try {
            _ = expr.block.traverse(this)
        } catch (e: BreakSignal) {
            break
        } catch (e: ContinueSignal) {
            continue
        }
        popScope()
    }
        inLoop = false
        //While 没有返回值
        return Value.VUnit
    }

    // 供 CallExpr 使用的函数调用实现
    private func callUserFunction(fn: UserFunction, call: CallExpr): Value {
        // 1. 参数数量检查
        let expected = fn.params.size
        let actual = call.arguments.size
        if (expected != actual) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.CALL_ARG_COUNT_MISMATCH,
                "Function `${fn.name}` expects ${expected} arguments, but got ${actual}",
                call
            )
        }

        let argValues = ArrayList<Value>()
        var idx: Int64 = 0
        for (arg in call.arguments.iterator()) {
            // 如果 Argument 里是 'expr' 字段，就用 arg.expr.traverse(this)
            // 如果你已经实现了 visit(Argument)，也可以直接 arg.traverse(this)
            let v = arg.traverse(this)
            argValues.add(v)

            // 形参类型检查（如果 RuntimeParam 里带了 type）
            let rp = fn.params[idx]
            if (rp.decltype.isSome()){
                let tyNode = rp.decltype.getOrThrow()
                match (tyNode) {
                    case t: PrimitiveType =>
                        let declared = t.typeName.value
                        let actualName = this.valType(v)
                        if (declared != actualName) {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.CALL_ARG_TYPE_MISMATCH,
                                "parameter ${idx} of function `${fn.name}` expects ${declared}, got ${actualName}",
                                arg              // 具体的实参位置
                            )
                        }
                    case _ =>
                        ()
                }
            }

            idx = idx + 1
        }

        let oldScopes = this.scopes
        let oldFunction = this.currentFunction
        this.scopes = ArrayList<HashMap<String, VarInfo>>()
        for (scope in fn.capturedScopes.iterator()) {
            this.scopes.add(scope)
        }
        
        this.currentFunction = Some(fn)
        
        this.pushScope()
        let paramScope = this.currentScope()

        // 4. 把形参名 -> 实参值 绑定到 paramScope 中（不可变 var）
        idx = 0
        while (idx < fn.params.size) {
            let rp = fn.params[idx]
            let argVal = argValues[idx]

            let paramName = rp.name
            paramScope[paramName] = VarInfo(
                false,             // 参数不可变
                None,       // 简化：不存 PrimitiveType，靠 valType 检查
                true,
                argVal,
                false
            )

            idx = idx + 1
        }

        //执行函数体，捕获 ReturnSignal
        var retVal: Value = Value.VUnit
        try {
            retVal = fn.body.traverse(this)
        } catch (e: ReturnSignal) {
            retVal = e.value
        }

        //调用结束，弹出参数作用域，并恢复之前的 scopes和函数上下文
        this.popScope()
        this.scopes = oldScopes
        this.currentFunction = oldFunction

        if (fn.returnType.isSome()) {
            let retTyNode = fn.returnType.getOrThrow()
            match (retTyNode) {
                case t: PrimitiveType =>
                    let declaredRet = t.typeName.value
                    let actualRet = this.valType(retVal)
                    if (declaredRet != actualRet) {
                        throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.FUNC_RETURN_TYPE_MISMATCH,
                            "function `${fn.name}` declared return type ${declaredRet}, but returned ${actualRet}",
                            call
                        )
                    }
                case _ =>
                    ()
            }
        }
        return retVal
    }

    public open override func visit(call: CallExpr): Value {
        // 1. 求值被调用者
        let calleeVal = call.callee.traverse(this)

        match (calleeVal) {
            // ---------- 内置函数 ----------
            case Value.VBuiltinFunction(bf) =>
                // 2. 检查参数个数
                let argCount = call.arguments.size
                if (bf.paramCount != argCount) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.CALL_ARG_COUNT_MISMATCH,
                        "builtin function `${bf.name}` expects ${bf.paramCount} arguments, but got ${argCount}",
                        call
                    )
                }
                // 3. 逐个计算实参
                let argValues = ArrayList<Value>()
                for (arg in call.arguments.iterator()) {
                    // Argument 的 visit 我们已经实现了，所以直接 traverse 即可
                    let v = arg.traverse(this)
                    argValues.add(v)
                }
                // 根据内置函数名字分派
                match (bf.name) {
                    case "println" =>
                        // println 只能有一个参数
                        this.callBuiltinPrintln(argValues[0])
                        return Value.VUnit

                    case _ =>
                        // 目前只实现了 println，其他内置函数暂不支持
                        throw Lab1TodoException("Unknown builtin function `${bf.name}`")
                }

            case Value.VFunction(f) =>
                return this.callUserFunction(f, call)

            case _ =>
                throw CjcjRuntimeErrorWithLocation(
                    ErrorCode.CALLEE_NOT_FUNCTION,
                    "callee is not a function: ${calleeVal.toValueString()}",
                    call
                )
        }
        return Value.VUnit
    }

    public open override func visit(ret: ReturnExpr): Value {
        var v = Value.VUnit

        if (ret.expr.isSome()) {
            v = ret.expr.getOrThrow().traverse(this)
        }

        throw ReturnSignal(v)
    }

    public open override func visit(jmp: JumpExpr): Value {
        match (jmp.keyword.kind) {
            // break 语句
            case TokenKind.BREAK =>
                if (!inLoop) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.BREAK_OUTSIDE_LOOP,
                        "`break` used outside of a while loop",
                        jmp
                    )
                }else {
                    inLoop = false
                    throw BreakSignal()
                }

            // continue 语句
            case TokenKind.CONTINUE =>
                if (!inLoop) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.CONTINUE_OUTSIDE_LOOP,
                        "`continue` used outside of a while loop",
                        jmp
                    )
                }
                throw ContinueSignal()

            // 其他跳转暂不支持
            case _ =>
                throw Lab1TodoException("Unknown Jump Expression `${jmp.keyword.kind}`")
        }

        // 理论上不会执行到这里
        return Value.VUnit
    }

    //变量声明
    public open override func visit(decl: VarDecl): Value {
        let name = decl.identifier.value    
        
        // 检查重定义       
        let current = this.currentScope()
        if (current.contains(name)) {
            throw CjcjRuntimeErrorWithLocation(ErrorCode.DUPLICATED_DEF,
            "Variable '${name}' is already defined in this scope", decl)
        
        }
        // 是否可变
        let isMutable = (decl.keyword.kind == TokenKind.VAR)

        // 提取声明类型
        var declaredType: ?PrimitiveType = None
        if (decl.declType.isSome()) {
            let typeNode = decl.declType.getOrThrow()
            match (typeNode) {
                case t: PrimitiveType => declaredType = Some(t)
                case _ => throw Lab1TodoException("Only primitive types are supported in Lab1")
            }
        }

        var initValue = Value.VUnit
        var initialized = false

        // 若有初始化表达式，先求值
        if (decl.initializer.isSome()) {
            initValue = decl.initializer.getOrThrow().traverse(this)
            initialized = true

            // 若声明了类型，需检查类型匹配
            match (declaredType) {
                case Some(t) => 
                    let actualType = this.valType(initValue)
                    if (t.typeName.value != actualType) {
                        throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.DEF_TYPE_MISMATCH,
                            "Variable '${name}' declared as ${t.typeName.value}, but assigned ${actualType}",
                            decl
                        )
                    }
                    
                case None =>  // 若未声明类型，则根据初始化值推断类型
                    match (initValue) {
                        case VInteger(_) => declaredType = Some(PrimitiveType(decl.id, Token(TokenKind.INT64, "Int", AstPos()), Token(TokenKind.INT64, "Int64", AstPos())))
                        case VString(_)  => declaredType = Some(PrimitiveType(decl.id, Token(TokenKind.STRING_LITERAL, "String", AstPos() ), Token(TokenKind.STRING_LITERAL, "String", AstPos())))
                        case VBoolean(_) => declaredType = Some(PrimitiveType(decl.id, Token(TokenKind.BOOLEAN, "Bool", AstPos()), Token(TokenKind.BOOLEAN, "Bool", AstPos())))
                        case VUnit       => declaredType = Some(PrimitiveType(decl.id, Token(TokenKind.UNIT, "Unit", AstPos()), Token(TokenKind.UNIT, "Unit", AstPos())))
                        case _ => throw Lab1TodoException("Only primitive types are supported in Lab1")
                    } 
            }
        }

        // 存储变量信息
        let isGlobalBinding = (this.scopes.size == 1)   // ★ 当前只有一层 scope 就是全局
        current[name] = VarInfo(
            isMutable,
            declaredType,
            initialized,
            initValue,
            isGlobalBinding
        )
        return Value.VUnit
    }


    public open override func visit(_: FuncParam): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Function Paramters")
    }

    public open override func visit(funcDecl: FuncDecl): Value {
        let name = funcDecl.identifier.value

        // 1. 检查同一作用域重定义（和 VarDecl 一样）
        let current = this.currentScope()
        if (current.contains(name)) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.DUPLICATED_DEF,
                "Variable or function '${name}' is already defined in this scope",
                funcDecl
            )
        }

        // 2. 检查是否缺少返回类型
        if (funcDecl.declType.isNone()) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.FUNC_MISSING_RETURN_TYPE,
                "Function '${name}' must declare a return type",
                funcDecl
            )
        }

        // 3. 检查是否缺少函数体
        if (funcDecl.block.isNone()) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.FUNC_MISSING_BODY,
                "Function '${name}' must have a body",
                funcDecl
            )
        }

        // 4. 收集参数：FuncParam -> RuntimeParam
        let runtimeParams = ArrayList<RuntimeParam>()
        for (p in funcDecl.params.iterator()) {
            let paramName = p.name.value
            let paramType: ?TypeNode = p.declType
            runtimeParams.add(RuntimeParam(paramName, paramType))
        }

        // 5. 捕获当前作用域栈作为闭包环境
        let captured = this.copyScopesForClosure()

        // 目前 defOrderInParent 先填 0，后面实现“忽略之后定义的变量”时再真正使用
        let defOrderInParent: Int64 = 0
        // 6. 构造 UserFunction
        let userFn = UserFunction(
            name,
            runtimeParams,
            funcDecl.declType,                  // 返回类型 AST
            funcDecl.block.getOrThrow(),        // 函数体 Block
            captured,
            defOrderInParent
        )

        //把函数当成一个不可变变量写进当前 scope
        let isGlobal = (this.scopes.size == 1)

        current[name] = VarInfo(
            false,                        // func 定义不可变
            None,
            true,
            Value.VFunction(userFn),
            isGlobal
        )

        return Value.VUnit
    }


    public open override func visit(mainDecl: MainDecl): Value {
        // main 自己的局部变量作用域
        this.pushScope()
        let result = mainDecl.block.traverse(this)
        this.popScope()

        // main 的求值结果作为整个程序的结果返回
        return result
    }


    public open override func visit(_: ClassDecl): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Class Declaration")
    }

    public open override func visit(body: Body): Value {
        var last: Value = Value.VUnit

        for (node in body.decls.iterator()) {
            last = node.traverse(this)
        }

        return last
    }

    public open override func visit(arg: Argument): Value {
        return arg.expr.traverse(this)
    }

    public open override func visit(_: TypeNode): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Type Node")
    }

    public open override func visit(_: PrimitiveType): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Primitive Types")
    }

    public open override func visit(_: RefType): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Reference Type")
    }

    public open override func visit(_: VariableReference): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Variable Reference (ASG)")
    }

    public open override func visit(_: FuncReference): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Function Reference (ASG)")
    }

    public open override func visit(_: ClassReference): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Class Reference (ASG)")
    }

    public open override func visit(_: VarDeclWithRef): Value {
        throw UnsupportedException(
            "Unimplemented method for Visitor : Variable Declaration with" + "References Stored (ASG)")
    }

    public open override func visit(_: FuncDeclWithRef): Value {
        throw UnsupportedException(
            "Unimplemented method for Visitor : Function Declaration with" + "References Stored (ASG)")
    }

    public open override func visit(_: MainDeclWithRef): Value {
        throw UnsupportedException(
            "Unimplemented method for Visitor : Main Declaration with" + "References Stored (ASG)")
    }

    public open override func visit(_: ClassDeclWithRef): Value {
        throw UnsupportedException(
            "Unimplemented method for Visitor : Class Declaration with" + "References Stored (ASG)")
    }

    public open override func visit(_: MemberAccess): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Member Access")
    }

    public open override func visit(_: PrimitiveTypeExpr): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Primitive type expression")
    }

    public open override func visit(_: RefExprWithRef): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Reference expression with reference")
    }

    public open override func visit(_: ThisSuperExpr): Value {
        throw UnsupportedException("Unimplemented method for Visitor : This Super expression")
    }

    public open override func visit(_: ThisSuperReference): Value {
        throw UnsupportedException("Unimplemented method for Visitor : This Super reference")
    }

    public open override func visit(_: CallExprWithRef): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Call expression with reference")
    }

    public open override func visit(_: MemberAccessWithRef): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Member access with reference")
    }

    public open override func visit(_: InterfaceDecl): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Interface Declaration")
    }

    public open override func visit(_: InterfaceDeclWithRef): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Interface Declaration with reference")
    }

    public open override func visit(_: InterfaceReference): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Interface Reference")
    }
}
