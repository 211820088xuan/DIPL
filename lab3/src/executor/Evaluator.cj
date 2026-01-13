package cjcj.executor
import cjcj.visitor.*
import cjcj.scanner.TokenKind
import cjcj.scanner.Token
import std.convert.*
import std.collection.*
import std.ast.Position as AstPos

class Lab1TodoException <: Exception {
    public init(message: String) {
        super("Lab 1 Exception: " + message)
    }
}

class Lab2TodoException <: Exception {
    public init(message: String) {
        super("Lab 2 Exception: " + message)
    }
}

class Lab3TodoException <: Exception {
    public init(message: String) {
        super("Lab 3 Exception: " + message)
    }
}


public class Classes {
    public let className: String
    public let fields = HashMap<String, VarInfo>()

    public init(className: String) {
        this.className = className
    }
}

//记录变量信息
public open class VarInfo {
    public let isMutable: Bool
    public let declaredType: ?TypeNode
    public var initialized: Bool
    public var value: Value
    public let isGlobal: Bool                 // ★ 新增：是否是全局绑定

    public init(isMut: Bool, declaredType: ?TypeNode, initialized: Bool, value: Value,isGlobal: Bool) {
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

    private var classTable = HashMap<String, Classes>()

    //当前类名（用于 this/super 检查）
    private var currentClassName: Option<String> = Option.None

    private var classDeclMap = HashMap<String, ClassDecl>()  // 新增：存储类声明映射


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
        global["Option"] = VarInfo(
            false,
            None,
            true,
            Value.VOption(OptionValue.ONone),
            true
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
            case Value.VObject(obj) => return obj.className  // ★ 返回类名而不是 "Object"
            case Value.VOption(_) => return "Option"
            case Value.VUninitialized => return "Uninitialized"
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
            case Value.VObject(obj) =>
                return "<Object of class ${obj.className}>"
            case Value.VOption(opt) =>
                match (opt) {
                    case OSome(v) => return "Some(${this.formatForBuiltinPrintln(v)})"
                    case ONone => return "None"
                }
            case Value.VUninitialized =>
                return "<Uninitialized Value>"         
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
                let newScope = HashMap<String, VarInfo>()
                for ((k, v) in scope.iterator()) {
                    newScope[k] = v
                }
                copied.add(newScope)
            }
            return copied
    }

    private func findFieldVarDecl(c: ClassDecl, name: String): VarDecl {
        for (d in c.body.decls.iterator()) {
            match (d) {
                case v: VarDecl =>
                    if (v.identifier.value == name) 
                    {
                        return v
                        }
                case _ => ()
            }
        }
        throw Exception("internal error: field not found " + name)
    }

    private func constructObject(className: String, call: CallExpr): Value {
        // 1. 查找类声明
        let classDeclOpt = this.findClassDecl(className)
        if (classDeclOpt.isNone()) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.UNDEFINED_CLASS,
                "Class '${className}' not defined",
                call
            )
        }
        
        let classDecl = classDeclOpt.getOrThrow()
        // 2. 获取类的静态信息（从 classTable）
        if (!this.classTable.contains(className)) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.UNDEFINED_CLASS,
                "Class '${className}' not properly initialized",
                call
            )
        }
        
        let classInfo = this.classTable[className]
        
        // 3. 创建空对象
        let obj = ObjectInstance(className)
        
        // 4. 初始化所有字段为 VUninitialized
        for ((fieldName, _) in classInfo.fields.iterator()) {
            obj.fields[fieldName] = Value.VUninitialized
        }

        for ((fieldName, fieldInfo) in classInfo.fields.iterator()) {
            match (fieldInfo.initialized) {
                case true =>
                    let vdecl = findFieldVarDecl(classDecl, fieldName)
                    let expr = vdecl.initializer.getOrThrow()
                    obj.fields[fieldName] = expr.traverse(this)

                case false => ()
            }
        }
        
        // 5. 查找并执行构造函数
        var constructorFound = false
        
        for (m in classDecl.body.decls.iterator()) {
            match (m) {
                case f: FuncDecl =>
                    if (f.identifier.kind == TokenKind.ILLEGAL) {  // 构造函数
                        constructorFound = true
                        
                        // 参数数量检查
                        if (f.params.size != call.arguments.size) {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.CALL_ARG_COUNT_MISMATCH,
                                "Constructor expects ${f.params.size} arguments, but got ${call.arguments.size}",
                                call
                            )
                        }
                        
                        // 进入新的作用域
                        this.pushScope()
                        
                        try {
                            // 在当前作用域注册 this
                            let scope = this.currentScope()
                            scope["this"] = VarInfo(
                                false,
                                None,
                                true,
                                Value.VObject(obj),  // 传入当前对象
                                false
                            )
                            
                            // 计算并绑定参数
                            var idx: Int64 = 0
                            for (param in f.params.iterator()) {
                                let arg = call.arguments[idx]
                                let argValue = arg.traverse(this)
                                
                                // 参数类型检查
                                match (param.declType) {
                                    case Some(typeNode) =>
                                        match (typeNode) {
                                            case pt: PrimitiveType =>
                                                let declared = pt.typeName.value
                                                let actual = this.valType(argValue)
                                                if (declared != actual) {
                                                    throw CjcjRuntimeErrorWithLocation(
                                                        ErrorCode.CALL_ARG_TYPE_MISMATCH,
                                                        "Constructor parameter ${param.name.value} expects ${declared}, got ${actual}",
                                                        arg
                                                    )
                                                }
                                            case _ => ()
                                        }
                                    case None => ()
                                }
                                
                                // 绑定参数
                                scope[param.name.value] = VarInfo(
                                    false,
                                    None,
                                    true,
                                    argValue,
                                    false
                                )
                                
                                idx = idx + 1
                            }
                            
                            // 执行构造函数体
                            f.block.getOrThrow().traverse(this)
                            
                        } finally {
                            this.popScope()
                        }
                        
                        break
                    }
                case _ => ()
            }
        }
        
        // 6. 如果没有显式构造函数，检查是否传入了参数
        if (!constructorFound && call.arguments.size > 0) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.CALL_ARG_COUNT_MISMATCH,
                "Class '${className}' has no constructor but ${call.arguments.size} arguments provided",
                call
            )
        }
        
        // 7. 检查所有字段是否已初始化
        for ((fieldName, value) in obj.fields.iterator()) {
            match (value) {
                case Value.VUninitialized =>
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.MEMBER_NOT_INITIALIZED_AFTER_INIT,
                        "Field '${fieldName}' of class '${className}' is not initialized after constructor",
                        call
                    )
                case _ => ()
            }
        }
        return Value.VObject(obj)
    }

    // 辅助函数：执行构造函数
    private func executeConstructor(constructor: FuncDecl, obj: ObjectInstance, call: CallExpr) {
        // 参数数量检查
        if (constructor.params.size != call.arguments.size) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.CALL_ARG_COUNT_MISMATCH,
                "Constructor expects ${constructor.params.size} arguments, but got ${call.arguments.size}",
                call
            )
        }
        
        // 进入新的作用域
        this.pushScope()
        
        try {
            // 在当前作用域注册 this
            let scope = this.currentScope()
            scope["this"] = VarInfo(
                false,
                None,
                true,
                Value.VObject(obj),
                false
            )
            
            // 计算并绑定参数
            var idx: Int64 = 0
            for (param in constructor.params.iterator()) {
                let arg = call.arguments[idx]
                let argValue = arg.traverse(this)
                
                // 参数类型检查
                match (param.declType) {
                    case Some(typeNode) =>
                        match (typeNode) {
                            case pt: PrimitiveType =>
                                let declared = pt.typeName.value
                                let actual = this.valType(argValue)
                                if (declared != actual) {
                                    throw CjcjRuntimeErrorWithLocation(
                                        ErrorCode.CALL_ARG_TYPE_MISMATCH,
                                        "Constructor parameter ${param.name.value} expects ${declared}, got ${actual}",
                                        arg
                                    )
                                }
                            case _ => ()
                        }
                    case None => ()
                }
                
                // 绑定参数
                scope[param.name.value] = VarInfo(
                    false,
                    None,
                    true,
                    argValue,
                    false
                )
                
                idx = idx + 1
            }
            
            // 执行构造函数体
            constructor.block.getOrThrow().traverse(this)
            
        } finally {
            this.popScope()
        }
    }

    private func buildMethodFunction(f: FuncDecl, obj: ObjectInstance): UserFunction {
        let captured = this.copyScopesForClosure()
        // 收集参数：FuncParam -> RuntimeParam
        let runtimeParams = ArrayList<RuntimeParam>()
        for (p in f.params.iterator()) {
            let paramName = p.name.value
            let paramType: ?TypeNode = p.declType
            runtimeParams.add(RuntimeParam(paramName, paramType))
        }

        // 在最里层 scope 注入 this
        let thisScope = HashMap<String, VarInfo>()
        thisScope["this"] = VarInfo(
            false, None, true,
            Value.VObject(obj),
            false
        )
        captured.add(thisScope)

        let fn = UserFunction(
            f.identifier.value,
            runtimeParams,
            f.declType,
            f.block.getOrThrow(),
            captured,
            0
        )
        
        return fn
    }

    private func findClassDecl(className: String): ?ClassDecl {
        if (this.classDeclMap.contains(className)) {
            return Some(this.classDeclMap[className])
        }
        return None
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

        // 2. 计算实参并做类型检查
        let argValues = ArrayList<Value>()
        var idx: Int64 = 0
        for (arg in call.arguments.iterator()) {
            let v = arg.traverse(this)
            argValues.add(v)

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
        this.scopes.add(oldScopes[0])
        for (scope in fn.capturedScopes.iterator()) {
            this.scopes.add(scope)
        }
        
        this.currentFunction = Some(fn)
        
        this.pushScope()
        let paramScope = this.currentScope()

        paramScope[fn.name] = VarInfo(
            false,                 // 函数名不可变
            None,
            true,
            Value.VFunction(fn),
            false
        )

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


    public open override func visit(prog: Program): Value {
        var mainDeclOpt: ?MainDecl = None

        // 第一步：声明所有类（只添加到类型系统，不检查内部）
        for (d in prog.decls.iterator()) {
            match (d) {
                case f: FuncDecl =>
                    f.traverse(this)
                case c: ClassDecl =>
                    // 先存储类声明到映射表
                    let className = c.identifier.value
                    if (this.classDeclMap.contains(className)) {
                        throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.DUPLICATED_DEF,
                            "Class '${className}' is already defined",
                            c
                        )
                    }
                    this.classDeclMap[className] = c
                    c.traverse(this)    
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
                ErrorCode.UNDEFINED_MEMBER,
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
                    throw CjcjRuntimeErrorWithLocation(ErrorCode.ASSIGN_IMMUT_DECL,
                        "cannot modify immutable variable '${name}'", expr)
                }

                scope[name] = info
                return Value.VUnit

            case ma: MemberAccess =>
                let objVal = ma.baseExpr.traverse(this)
                match (objVal) {
                    case Value.VObject(obj) =>
                        let fieldName = ma.field.value
                        if (!obj.fields.contains(fieldName)) {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.UNDEFINED_MEMBER,
                                "undefined member '${fieldName}'",
                                expr
                            )
                        }
                        let v = expr.right.traverse(this)
                        obj.fields[fieldName] = v
                        return Value.VUnit
                    case _ =>
                        throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.MEMBER_ASSIGN_NON_OBJECT,
                            "assign to non-object",
                            expr
                        )
                }
    
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

    public open override func visit(call: CallExpr): Value {
        // 1 构造函数 / Option.Some / None（语法级）
        match (call.callee) {
            case ref: RefExpr =>
                let className = ref.identifier.value
                if (this.classTable.contains(className)) {
                    return this.constructObject(className, call)
                }

            case ma: MemberAccess =>
                match (ma.baseExpr) {
                    case ref: RefExpr =>
                        
                        let scope = this.findScope(ref.identifier.value).getOrThrow()
                        let info = scope.get(ref.identifier.value).getOrThrow()
                        if (ref.identifier.value == "Option" || info.value.toValueString() == "Option") {
                            match (ma.field.value) {
                                // print("ma.field.value = ${ma.field.value}")
                                case "Some" =>
                                    if (call.arguments.size != 1) {
                                        throw CjcjRuntimeErrorWithLocation(
                                            ErrorCode.CALL_ARG_COUNT_MISMATCH,
                                            "Option.Some expects 1 argument",
                                            call
                                        )
                                    }
                                    let v = call.arguments[0].traverse(this)
                                    return Value.VOption(OptionValue.OSome(v))
                                case "isSome" =>
                                    if (call.arguments.size != 0) {
                                        throw CjcjRuntimeErrorWithLocation(
                                            ErrorCode.CALL_ARG_COUNT_MISMATCH,
                                            "Option.isSome expects none argument",
                                            call
                                        )
                                    }
                                    match (info.value) {
                                        case Value.VOption(opt) =>
                                            match (opt) {
                                                case OSome(_) => return Value.from(true)
                                                case ONone    => return Value.from(false)
                                            }
                                        case _ =>
                                            throw CjcjRuntimeErrorWithLocation(
                                                ErrorCode.OPTION_METHOD_ON_NON_OPTION,
                                                "Option.isSome called on non-Option value: ${info.value.toValueString()}",
                                                call
                                            )
                                    }
                                case "isNone" =>
                                    if (call.arguments.size != 0) {
                                        throw CjcjRuntimeErrorWithLocation(
                                            ErrorCode.CALL_ARG_COUNT_MISMATCH,
                                            "Option.isNone expects none argument",
                                            call
                                        )
                                    }
                                    match (info.value) {
                                        case Value.VOption(opt) =>
                                            match (opt) {
                                                case OSome(_) => return Value.from(false)
                                                case ONone    => return Value.from(true)
                                            }
                                        case _ =>
                                            throw CjcjRuntimeErrorWithLocation(
                                                ErrorCode.OPTION_METHOD_ON_NON_OPTION,
                                                "Option.isNone called on non-Option value: ${info.value.toValueString()}",
                                                call
                                            )
                                    }
                                case "getOrThrow" =>
                                    if (call.arguments.size != 0) {
                                        throw CjcjRuntimeErrorWithLocation(
                                            ErrorCode.CALL_ARG_COUNT_MISMATCH,
                                            "Option.getOrThrow expects 0 arguments",
                                            call
                                        )
                                    }
                                    match (info.value) {
                                        case Value.VOption(opt) =>
                                            match (opt) {
                                                case OSome(innerVal) => return innerVal
                                                case ONone =>
                                                    throw CjcjRuntimeErrorWithLocation(
                                                        ErrorCode.OPTION_UNWRAP_NONE,
                                                        "Option.getOrThrow: ${"called on None value"}",
                                                        call
                                                    )
                                            }
                                        case _ =>
                                            throw CjcjRuntimeErrorWithLocation(
                                                ErrorCode.OPTION_METHOD_ON_NON_OPTION,
                                                "Option.getOrThrow called on non-Option value: ${info.value.toValueString()}",
                                                call
                                            )
                                    } 
                                case _ => ()
                            }
                            return ma.traverse(this)
                        }
                    case _ => ()
             } 
            case _ => ()
        }

        // 计算被调用者
        let calleeVal = call.callee.traverse(this)

        // 2. 根据被调用者类型分派
        match (calleeVal) {
            // ---------- 内置函数 ----------
            case Value.VBuiltinFunction(bf) =>
                // 参数数量检查
                let argCount = call.arguments.size
                if (bf.paramCount != argCount) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.CALL_ARG_COUNT_MISMATCH,
                        "builtin function `${bf.name}` expects ${bf.paramCount} arguments, but got ${argCount}",
                        call
                    )
                }
                // 逐个计算实参
                let argValues = ArrayList<Value>()
                for (arg in call.arguments.iterator()) {
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
        var declaredType: ?TypeNode = None
        if (decl.declType.isSome()) {
            let typeNode = decl.declType.getOrThrow()
            match (typeNode) {
                // case t: PrimitiveType => declaredType = Some(t)
                case t: TypeNode     => declaredType = Some(t)
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
                    
                    //  特殊处理：对象类型检查
                    match (t) {
                        case rt: RefType =>
                            // 引用类型（类类型）
                            let declaredClassName = rt.typeName.value
                            
                            match (initValue) {
                                case Value.VObject(obj) =>
                                    // 检查对象的类是否匹配声明的类
                                    if (obj.className != declaredClassName) {
                                        throw CjcjRuntimeErrorWithLocation(
                                            ErrorCode.DEF_TYPE_MISMATCH,
                                            "Variable '${name}' declared as ${declaredClassName}, " +
                                            "but assigned object of class ${obj.className}",
                                            decl
                                        )
                                    }
                                    // 类型匹配，继续
                                case _ =>
                                    // 不是对象，类型不匹配
                                    if (declaredClassName != actualType) {
                                        throw CjcjRuntimeErrorWithLocation(
                                            ErrorCode.DEF_TYPE_MISMATCH,
                                            "Variable '${name}' declared as ${declaredClassName}, " +
                                            "but assigned ${actualType}",
                                            decl
                                        )
                                    }
                                case _ => ()    
                            }
                            
                        case pt: PrimitiveType =>
                            // 基本类型检查（保持不变）
                            let declaredTypeName = pt.typeName.value
                            if (declaredTypeName != actualType) {
                                throw CjcjRuntimeErrorWithLocation(
                                    ErrorCode.DEF_TYPE_MISMATCH,
                                    "Variable '${name}' declared as ${declaredTypeName}, " +
                                    "but assigned ${actualType}",
                                    decl
                                )
                            }
                        case _ => throw Lab1TodoException("Only primitive types are supported in Lab1")    
                    }
                    
                case None =>  // 若未声明类型，则根据初始化值推断类型
                    match (initValue) {
                        case VInteger(_) => declaredType = Some(PrimitiveType(decl.id, Token(TokenKind.INT64, "Int", AstPos()), Token(TokenKind.INT64, "Int64", AstPos())))
                        case VString(_)  => declaredType = Some(PrimitiveType(decl.id, Token(TokenKind.STRING_LITERAL, "String", AstPos() ), Token(TokenKind.STRING_LITERAL, "String", AstPos())))
                        case VBoolean(_) => declaredType = Some(PrimitiveType(decl.id, Token(TokenKind.BOOLEAN, "Bool", AstPos()), Token(TokenKind.BOOLEAN, "Bool", AstPos())))
                        case VUnit       => declaredType = Some(PrimitiveType(decl.id, Token(TokenKind.UNIT, "Unit", AstPos()), Token(TokenKind.UNIT, "Unit", AstPos())))
                        case VOption (_) => declaredType = Some(TypeNode(decl.id, Token(TokenKind.OPTION, "Option", AstPos()), Token(TokenKind.OPTION, "Option", AstPos())))
                        case VObject(obj) => 
                            // 对象类型推断
                            // 正确创建 RefType 实例
                            declaredType = Some(RefType(
                                decl.id,                           // 节点ID
                                Token(TokenKind.IDENTIFIER, obj.className, AstPos()),  // 类型参数名Token
                                Token(TokenKind.IDENTIFIER, obj.className, AstPos()),  // 类型名Token
                                ArrayList<TypeNode>()              // 空类型参数列表
                            ))
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


    public open override func visit(c: ClassDecl): Value {

        let className = c.identifier.value
        // 1. 检查类是否已经定义
        if (this.classTable.contains(className)) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.DUPLICATED_DEF,
                "Class '${className}' is already defined",
                c
            )
        }
        
        // 2. 创建Classes实例来存储类的静态信息
        let classInfo = Classes(className)

         //  记录当前类名（用于方法中的this引用）
        let previousClass = currentClassName
        this.currentClassName = Option.Some(c.identifier.value)
        pushScope()
        
        // 2. 在当前作用域注册"this"变量
        let scope = this.currentScope()
        scope["this"] = VarInfo(
            false,               // 不可变
            None,                // 类型暂不处理
            true,                // 已初始化
            Value.VUninitialized,// 实际值将在构造函数中设置
            false                // 不是全局绑定
        )

        // 处理类体中的静态成员（如果有）
        // 注意：根据仓颉语言的特性，可能没有静态成员
        for (decl in c.body.decls.iterator()) {
            match (decl) {
                case f: FuncDecl =>
                    // 处理函数声明
                    // 1. 检查构造函数的特殊规则
                    var methodName = f.identifier.value
                    if (f.keyword.value == "init") {
                        // 这是构造函数（init）
                        // 检查构造函数是否返回类型
                        if (f.declType.isSome()) {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.CONSTRUCTOR_RETURN_TYPE,
                                "Constructor cannot have a return type",
                                f
                            )
                        }
                        methodName = "init"
                    }
                    
                    // 2. 检查方法是否重定义
                    if (scope.contains(methodName)) {
                        throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.DUPLICATED_DEF,
                            "Method '${methodName}' is already defined in class '${c.identifier.value}'",
                            f
                        )
                    }
                    
                    // 3. 将方法视为类作用域内的"变量"
                    let isGlobal = false
                    let isInitialized = true
                    
                    // 创建方法的环境（不包含对象实例，因为还没有对象）
                    let runtimeParams = ArrayList<RuntimeParam>()
                    for (p in f.params.iterator()) {
                        let paramName = p.name.value
                        let paramType: ?TypeNode = p.declType
                        runtimeParams.add(RuntimeParam(paramName, paramType))
                    }
                    
                    // 复制当前作用域作为闭包环境（不包含上层对象实例）
                    let captured = this.copyScopesForClosure()
                    
                    let userFn = UserFunction(
                        methodName,
                        runtimeParams,
                        f.declType,
                        f.block.getOrThrow(),
                        captured,
                        0
                    )
                    
                    // 将方法存入类作用域
                    scope[methodName] = VarInfo(
                        false,               // 不可变
                        None,                // 类型信息
                        isInitialized,
                        Value.VFunction(userFn),
                        isGlobal
                    )
                case v: VarDecl =>
                    let fieldName = v.identifier.value
                    let t = v.declType

                    classInfo.fields[fieldName] = VarInfo(
                        v.keyword.kind == TokenKind.VAR,   // 是否 mutable
                        t,                                 // 声明类型
                        v.initializer.isSome(),            // 标记“是否有默认初始化器”
                        Value.VUninitialized,              // 当前值 = 未初始化（延后处理）
                        false
                    )
                case _ =>
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.UNSUPPORTED_DECL_IN_CLASS,
                        "Unsupported declaration type in class body",
                        decl
                )
            }
        }
        
        // 7. 将Classes存储到classTable
        this.classTable[className] = classInfo

        // 恢复状态
        this.popScope()
        this.currentClassName = previousClass

        return Value.VUnit
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

    public open override func visit(ma: MemberAccess): Value {
        // 1. 先求 baseExpr
        let baseVal = ma.baseExpr.traverse(this)
        let name = ma.field.value

        match (baseVal) {
            // ================= Object 成员访问 =================
            case Value.VObject(obj) =>
                // —— 字段访问 ——
                if (obj.fields.contains(name)) {
                    let v = obj.fields[name]
                    match (v) {
                        case Value.VUninitialized =>
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.UNINITIALIZED_VAR,
                                "field '${name}' used before initialization",
                                ma
                            )
                        case _ => return v
                    }
                }

                // —— 方法访问 ——
                if (!this.classTable.contains(obj.className)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.UNDEFINED_MEMBER,
                        "undefined class '${obj.className}'",
                        ma
                    )
                }

                let classDecl = this.findClassDecl(obj.className)

                if (classDecl.isNone()) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.UNDEFINED_MEMBER,
                        "undefined class '${obj.className}'",
                        ma
                    )
                }
                let decl = classDecl.getOrThrow()
                // 在类声明中查找方法
                for (m in decl.body.decls.iterator()) {
                    match (m) {
                        case f: FuncDecl =>
                            if (f.identifier.value == name && f.identifier.kind != TokenKind.ILLEGAL) {
                                return Value.VFunction(
                                    this.buildMethodFunction(f, obj)
                                )
                            }
                        case _ => ()
                    }
                }

                throw CjcjRuntimeErrorWithLocation(
                    ErrorCode.UNDEFINED_MEMBER,
                    "class '${obj.className}' has no member '${name}'",
                    ma
                )

            // ================= Option 实例方法 =================
            case Value.VOption(opt) =>
                match (name) {
                    case "None" =>
                        return Value.VOption(OptionValue.ONone)    
                    case _ =>
                        throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.UNDEFINED_MEMBER,
                            "Option has no member '${name}'",
                            ma
                        )    
                }
            
            // ================= 非法访问 =================
            case _ =>
                println("Base value for member access is: ${baseVal.toValueString()}")
                throw CjcjRuntimeErrorWithLocation(
                    ErrorCode.MEMBER_ACCESS_NON_OBJECT,
                    "member access on non-object value",
                    ma
                )  
        }
    }



    public open override func visit(_: PrimitiveTypeExpr): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Primitive type expression")
    }

    public open override func visit(_: RefExprWithRef): Value {
        throw UnsupportedException("Unimplemented method for Visitor : Reference expression with reference")
    }

    public open override func visit(node: ThisSuperExpr): Value {
        let keyword = node.keyword
        
        if (keyword.kind != TokenKind.THIS) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.INVALID_THIS,
                "Only 'this' is supported, 'super' not yet implemented",
                node
            )
        }
        
        // 查找 "this" 变量
        let scopeOpt = this.findScope("this")
        if (scopeOpt.isNone()) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.THIS_SUPER_OUTSIDE_CLASS,
                "'this' can only be used inside class methods or constructors",
                node
            )
        }
        
        let scope = scopeOpt.getOrThrow()
        let varInfo = scope.get("this").getOrThrow()
        
        // 检查是否已初始化
        if (!varInfo.initialized) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.UNINITIALIZED_VAR,
                "'this' refers to an uninitialized object",
                node
            )
        }
        
        // 检查值是否为对象
        match (varInfo.value) {
            case Value.VObject(_) =>
                return varInfo.value
            case Value.VUninitialized =>
                throw CjcjRuntimeErrorWithLocation(
                    ErrorCode.UNINITIALIZED_VAR,
                    "'this' object is not fully initialized",
                    node
                )
            case _ =>
                throw CjcjRuntimeErrorWithLocation(
                    ErrorCode.INVALID_THIS,
                    "'this' must refer to a class instance",
                    node
                )
        }
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
