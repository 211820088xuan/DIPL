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

    public init(isMut: Bool, declaredType: ?PrimitiveType, initialized: Bool, value: Value) {
        this.isMutable = isMut
        this.declaredType = declaredType
        this.initialized = initialized
        this.value = value
    }
}

public class BreakSignal <: Exception {}
public class ContinueSignal <: Exception {}



/** 
 * Evaluator Visitor
 *
 * Lab1 TODO: We have given the simplest form, each `Node` will return a `Value` after evaluation.
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
    private let static_scope : Int64  = 0;

    //是否在循环中
    private var inLoop = false


    public init() {
        this.scopes = ArrayList<HashMap<String, VarInfo>>() // 全局作用域
        this.scopes.add(HashMap<String, VarInfo>())
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

        // If not found, return an empty map
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
        }
    }


    public open override func visit(_: Program): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Program")
    }

    // This is just an example of how to implement the visit method for BinaryExpr.
    // You may need to modify, split, or completely rewrite it depending on your design.

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
                        "cannot add left = ${left}, right = ${right}", expr)
                }
                case TokenKind.SUB => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a - b)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.SUB_TYPE_MISMATCH,
                        "cannot subtract ${left} and ${right}", expr)
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
                            "cannot multiply left = ${left}, right = ${right}",
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
                        "cannot divide ${left} and ${right}", expr)
                }
                case TokenKind.MOD => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) =>
                        if (b == 0) {
                            throw CjcjRuntimeErrorWithLocation(ErrorCode.MOD_BY_ZERO, "modulo by zero", expr)
                        }
                        Value.from(a % b)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.MOD_TYPE_MISMATCH,
                        "cannot modulo ${left} and ${right}", expr)
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
                        "cannot exponentiate ${left} to the power of ${right}", expr)
                }
                //比较操作
                case TokenKind.LT => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a < b)  // 返回 VBoolean 类型
                    case _ => throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.CMP_TYPE_MISMATCH,
                        "cannot compare left = ${left} with right = ${right}", expr
                    )
                }
                case TokenKind.GT => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a > b)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.CMP_TYPE_MISMATCH,
                        "cannot compare left = ${left} with right = ${right}", expr)
                }

                case TokenKind.LE => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a <= b)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.CMP_TYPE_MISMATCH,
                        "cannot compare left = ${left} with right = ${right}", expr)
                }

                case TokenKind.GE => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a >= b)
                    case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.CMP_TYPE_MISMATCH,
                        "cannot compare left = ${left} with right = ${right}", expr)
                }
                case TokenKind.EQUAL => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a == b)
                    case (VBoolean(a), VBoolean(b)) => Value.from(a == b)
                    case (VString(a), VString(b))   => Value.from(a == b)
                    case _ => throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.EQ_TYPE_MISMATCH,
                        "cannot compare left = ${left} with right = ${right}", expr
                    )
                }
                case TokenKind.NOTEQ => match ((left, right)) {
                    case (VInteger(a), VInteger(b)) => Value.from(a != b)
                    case (VBoolean(a), VBoolean(b)) => Value.from(a != b)
                    case (VString(a), VString(b))   => Value.from(a != b)
                    case _ => throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.NEQ_TYPE_MISMATCH,
                        "cannot compare left = ${left} with right = ${right}", expr
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
                                        "logical and requires Bool operands but got right = ${rightValue}",
                                        expr
                                    )
                                }
                            }
                        case _ => throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.AND_TYPE_MISMATCH,
                            "logical and requires Bool operands but got left = ${leftValue}",
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
                                        "logical or requires Bool operands but got right = ${rightValue}",
                                        expr
                                    )
                                }
                            }
                        case _ => throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.OR_TYPE_MISMATCH,
                            "logical or requires Bool operands but got left = ${leftValue}",
                            expr
                        )
                    }
                
                case _ => throw Lab1TodoException("Unimplemented Binary Operator `${expr.oper.kind}`")
            }
        } catch (e: OverflowException) {
            match (e.message) {
                case "add" => throw CjcjRuntimeErrorWithLocation(ErrorCode.ADD_OVERFLOW,
                    "overflow add: left = ${left}, right = ${right}", expr)
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
                            "negation overflow: ${v}", expr)
                    }
                case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.NEG_TYPE_MISMATCH,
                    "negation requires Int64 but got ${v}", expr)
            }

            // 逻辑非
            case TokenKind.NOT => match (v) {
                case VBoolean(b) => return Value.from(!b)
                case _ => throw CjcjRuntimeErrorWithLocation(ErrorCode.NOT_TYPE_MISMATCH,
                    "logical not requires Bool but got ${v}", expr)
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
                    throw CjcjRuntimeErrorWithLocation(ErrorCode.ASSGIN_IMMUT_VAR,
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
        let scope = this.findScope(name)
        if (scope.isNone()) {
            throw CjcjRuntimeErrorWithLocation(ErrorCode.UNDEFINED_VAR,
                "undefined variable '${name}'", ref)
        }
        let optscope = scope.getOrThrow()
        let info = optscope.get(name).getOrThrow()
        if (!info.initialized) {
            throw CjcjRuntimeErrorWithLocation(ErrorCode.UNINITIALIZED_VAR,
                "variable '${name}' used before initialization", ref)
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
        // 执行循环体
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

    public open override func visit(call: CallExpr): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Call Expression")
    }

    public open override func visit(_: ReturnExpr): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Return Expression")
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
                    } 
            }
        }

        // 存储变量信息
        current[name] = VarInfo(isMutable, declaredType, initialized, initValue)
        return Value.VUnit
    }


    public open override func visit(_: FuncParam): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Function Paramters")
    }

    public open override func visit(_: FuncDecl): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Function Declaration")
    }

    public open override func visit(_: MainDecl): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Main Declaration")
    }

    public open override func visit(_: ClassDecl): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Class Declaration")
    }

    public open override func visit(_: Body): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Body")
    }

    public open override func visit(arg: Argument): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Argument")
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
