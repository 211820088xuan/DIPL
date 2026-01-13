package cjcj.executor

import std.collection.*
import cjcj.visitor.*
import cjcj.scanner.TokenKind
import cjcj.scanner.Token

public class TCVarInfo {
    public let ty: StaticType
    public let isMutable: Bool
    public let isGlobal: Bool

    public init(ty: StaticType, isMutable: Bool, isGlobal: Bool) {
        this.ty = ty
        this.isMutable = isMutable
        this.isGlobal = isGlobal
    }
}


public class TypeChecker <: Visitor<StaticType> {

    init() {
        scopes.add(HashMap<String, TCVarInfo>()) // global scope
    }

    // ========= 全局类型表 =========
    private let classes = HashMap<String, ClassInfo>()

    // 局部作用域栈
    private let scopes = ArrayList<HashMap<String, TCVarInfo>>()

    // 控制流辅助状态
    private var loopDepth: Int64 = 0
    private var currentFuncRetType: Option<StaticType> = Option.None
    private var currentClassName: Option<String> = Option.None
    private var funcDepth: Int64 = 0
    // 追踪当前类
    private var currentClass: Option<String> = Option.None


    private func currentScope() : HashMap<String, TCVarInfo> {
        return this.scopes[this.scopes.size - 1]
    }

    // private func typeError(code: ErrorCode, n: Node): Nothing {
    //     throw CjcjRuntimeErrorWithLocation(code, code.toString(), n)
    // }

    private func expectBool(t: StaticType, n: Node, code: ErrorCode): Unit {
        if (!(t == StaticType.TBool)) {
            throw CjcjRuntimeErrorWithLocation(
                code,
                "Expected Bool type, but got ${t.toString()}",
                n
            )
        }
    }

    private func expectSubtype(got: StaticType, expected: StaticType, n: Node, code: ErrorCode): Unit {
        if (!isSubtype(got, expected)) {
            throw CjcjRuntimeErrorWithLocation(
                code,
                "Expected type ${expected.toString()}, but got ${got.toString()}",
                n
            )
        }
    }

    private func isOptionType(t: StaticType): Bool {
        match (t) {
            case StaticType.TOption(_) => true
            case _ => false
        }
    }

    private func optionInner(t: StaticType, n: Node): StaticType {
        match (t) {
            case StaticType.TOption(inner) => inner
            case _ => 
                throw CjcjRuntimeErrorWithLocation(
                    ErrorCode.OPTION_IS_NONE,
                    "Expected Option type, but got ${t.toString()}",
                    n
                )
        }
    }
    

    // ========= 对外入口 =========

    public func checkProgram(program: Program): Unit {
        // pass 1：收集所有声明的“签名”
        for (d in program.decls.iterator()) {
            collectDeclSignature(d)
        }

        // pass 2：检查声明体（现在只是遍历，不细查）
        for (d in program.decls.iterator()) {
            checkDeclBody(d)
        }
    }

    // ========= 第一遍：只收集签名 =========

    private func collectDeclSignature(decl: Decl): Unit {
        match (decl) {
            case v: VarDecl => 
                let t = fromTypeNode(v.declType.getOrThrow())
                scopes[0][v.identifier.value] = TCVarInfo(t, (v.keyword.kind == TokenKind.VAR), true)
            case f: FuncDecl => 
                let paramTypes = ArrayList<StaticType>()
                for (p in f.params.iterator()) {
                    // 某些语法树里 paramType 在 paramType 字段里
                    let tyNode =
                        if (p.declType.isSome())
                        { p.declType.getOrThrow()}
                        else 
                        {p.paramType}
                    paramTypes.add(fromTypeNode(tyNode))
                }

                // ====== 是不是类里的方法？ ======
                if (currentClass.isSome()) {
                    let clsName = currentClass.getOrThrow()
                    let info = classes[clsName]

                    // ====== init(): 作为构造函数 ======
                    if (f.keyword.value == "init") {
                        info.ctor = Option.Some(
                            StaticType.TFunc(paramTypes, StaticType.TUnit)
                        )

                    } else {
                        // ====== 普通实例方法 ======
                        let ret = fromTypeNode(f.declType.getOrThrow())
                        info.methods[f.identifier.value] =
                            StaticType.TFunc(paramTypes, ret)
                    }

                } else {
                    // ====== 全局函数 ======
                    let r = fromTypeNode(f.declType.getOrThrow())
                    scopes[0][f.identifier.value] =
                        TCVarInfo(StaticType.TFunc(paramTypes, r), false, false)
                }

            case m: MainDecl => 
                //保证main无参数
                scopes[0]["main"] = TCVarInfo(StaticType.TFunc(ArrayList<StaticType>(), StaticType.TUnit), false, false)
            case c: ClassDecl => 
                let className = c.identifier.value
                let info = ClassInfo(className)

                // 遍历 class body
                for (d in c.body.decls.iterator()) {
                    match (d) {

                        // 字段
                        case v: VarDecl => 
                            let t = fromTypeNode(v.declType.getOrThrow())
                            info.fields[v.identifier.value] = t
                            // 默认未初始化（如果字段有 initializer，则视为已初始化）
                            info.fieldInitialized[v.identifier.value] = v.initializer.isSome()
                        // 方法
                        case f: FuncDecl => 
                            let paramTypes = ArrayList<StaticType>()
                            for (p in f.params.iterator()) {
                                let tyNode =
                                    if (p.declType.isSome()) {
                                        p.declType.getOrThrow()
                                    } else {
                                        p.paramType
                                    }
                                paramTypes.add(fromTypeNode(tyNode))    
                            }
                            let ret =
                                if (f.declType.isSome()) {
                                    fromTypeNode(f.declType.getOrThrow())
                                } else {
                                    StaticType.TUnit   // init() / 无返回类型
                                }
                            info.methods[f.identifier.value] =
                                StaticType.TFunc(paramTypes, ret)

                        // 构造函数（如果你语法支持）
                        case _ => ()
                    }
                }

                classes[className] = info

            case _ => throw Exception("unknown decl type in collecting: " + decl.identifier.value)
        }
    }

    // ========= 第二遍：检查体（当前是“空壳遍历版”） =========
    private func checkDeclBody(decl: Decl): Unit {
        match (decl) {

            case v: VarDecl => 
                v.traverse(this)

            case f: FuncDecl => 
                enterScope()
                funcDepth = funcDepth + 1
                currentFuncRetType = Option.Some(fromTypeNode(f.declType.getOrThrow()))

                let scope = currentScope()
                for (p in f.params.iterator()) {
                    scope[p.identifier.value] =
                        TCVarInfo(fromTypeNode(p.declType.getOrThrow()), false, false)
                }

                f.block.getOrThrow().traverse(this)
                // Special check for init method
                let isInit = (f.identifier.value == "init")
                if (isInit && currentClassName.isSome()) {
                    let cls = currentClassName.getOrThrow()
                    let info = classes[cls]

                    for ((fname, done) in info.fieldInitialized) {
                        if (!done) {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.MEMBER_NOT_INITIALIZED_AFTER_INIT,
                                "Field '${fname}' is not initialized after init().",
                                f
                            )
                        }
                    }
                }

                funcDepth = funcDepth - 1
                currentFuncRetType = Option.None
                exitScope()


            case m: MainDecl => 
                enterScope()
                m.block.traverse(this)
                exitScope()
            
            case c: ClassDecl => 
                currentClassName = Option.Some(c.identifier.value)
                enterScope()

                // this
                currentScope()["this"] = TCVarInfo(StaticType.TClass(c.identifier.value), false, false)

                for (d in c.body.decls.iterator()) {
                    d.traverse(this)
                }

                exitScope()
                currentClassName = Option.None

            case _ => throw Exception("unknown decl type in checking: " + decl.identifier.value)
        }
    }

    // ========= 作用域管理 =========

    private func enterScope(): Unit {
        scopes.add(HashMap<String, TCVarInfo>())
    }

    private func exitScope(): Unit {
        scopes.remove(at: scopes.size - 1)
    }

    private func lookupVar(name: String): Option<TCVarInfo> {
        for (i in scopes.size - 1 .. -1) {
            let scope = scopes[i]
            if (scope.contains(name)) {
                return Option.Some(scope.get(name).getOrThrow())
            }
        }
        return Option.None
    }

    public override func visit(prog: Program): StaticType {
        checkProgram(prog)
        return StaticType.TUnit
    }

    // ========= Expr 访问器 =========

    public override func visit(lit: LitConstExpr): StaticType {
        match (lit.literal.kind) {
            case TokenKind.INTEGER_LITERAL => StaticType.TInt64
            case TokenKind.STRING_LITERAL  => StaticType.TString
            case TokenKind.BOOL_LITERAL    => StaticType.TBool
            case TokenKind.UNIT_LITERAL    => StaticType.TUnit
            case _ => StaticType.TUnit
        }
    }


    public override func visit(r: RefExpr): StaticType {
        let name = r.identifier.value

        // ========= 1. 查找变量 =========
        var foundInfo: Option<TCVarInfo> = Option.None
        var foundScopeIndex: Int64 = -1

        var i = scopes.size - 1
        while (i >= 0) {
            let scope = scopes[i]
            if (scope.contains(name)) {
                foundInfo = Option.Some(scope.get(name).getOrThrow())
                foundScopeIndex = i
                break
            }
            i = i - 1
        }

        if (foundInfo.isNone()) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.UNDEFINED_VAR,
                "Variable '${name}' is not defined.",
                r
            )
        }

        let info = foundInfo.getOrThrow()

        // ========= 2. 闭包规则检查 =========
        // 在函数内部
        if (currentFuncRetType.isSome()) {
            let currentScopeIndex = scopes.size - 1

            let isNonLocal = foundScopeIndex < currentScopeIndex

            if (isNonLocal && !info.isGlobal && info.isMutable) {
                throw CjcjRuntimeErrorWithLocation(
                    ErrorCode.FUNC_USE_MUTABLE_NONLOCAL,
                    "Cannot access mutable non-local variable '${name}' in function.",
                    r
                )
            }
        }

        return info.ty
    }



    public override func visit(u: UnaryExpr): StaticType {
        let rhs = u.right.traverse(this)

        match (u.oper.kind) {
            case TokenKind.SUB =>
                if (!(rhs == StaticType.TInt64)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.NEG_TYPE_MISMATCH,
                        "Expected Int64 type, but got ${rhs.toString()}",
                        u
                    )
                }
                StaticType.TInt64

            case TokenKind.NOT =>
                if (!(rhs == StaticType.TBool)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.NOT_TYPE_MISMATCH,
                        "Expected Bool type, but got ${rhs.toString()}",
                        u
                    )
                }
                StaticType.TBool

            case _ =>
                StaticType.TUnit
        }
    }


    public override func visit(b: BinaryExpr): StaticType {
        let l = b.left.traverse(this)
        let r = b.right.traverse(this)

        match (b.oper.kind) {

            case TokenKind.ADD =>
                if (l == StaticType.TInt64 && r == StaticType.TInt64) {
                    StaticType.TInt64
                } else if (l == StaticType.TString && r == StaticType.TString) {
                    StaticType.TString
                } else {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.ADD_TYPE_MISMATCH,
                        "Expected both sides to be Int64 or both sides to be String, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }

            case TokenKind.SUB =>
                if (!(l == StaticType.TInt64 && r == StaticType.TInt64)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.SUB_TYPE_MISMATCH,
                        "Expected both sides to be Int64, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TInt64
            case TokenKind.MUL =>
                if (!((l == StaticType.TInt64 && r == StaticType.TInt64) || (l == StaticType.TString && r == StaticType.TInt64) || (l == StaticType.TInt64 && r == StaticType.TString))) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.MUL_TYPE_MISMATCH,
                        "Expected both sides to be Int64 or one side to be String and the other to be Int64, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TInt64
            case TokenKind.DIV =>
                if (!(l == StaticType.TInt64 && r == StaticType.TInt64)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.DIV_TYPE_MISMATCH,
                        "Expected both sides to be Int64, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TInt64
            case TokenKind.MOD =>
                if (!(l == StaticType.TInt64 && r == StaticType.TInt64)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.MOD_TYPE_MISMATCH,
                        "Expected both sides to be Int64, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TInt64
            case TokenKind.EXP =>
                if (!(l == StaticType.TInt64 && r == StaticType.TInt64)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.EXP_TYPE_MISMATCH,
                        "Expected both sides to be Int64, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TInt64        
            case TokenKind.LT =>
                if (!(l == StaticType.TInt64 && r == StaticType.TInt64)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.CMP_TYPE_MISMATCH,
                        "Expected both sides to be Int64, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TBool
            case TokenKind.LE =>
                if (!(l == StaticType.TInt64 && r == StaticType.TInt64)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.CMP_TYPE_MISMATCH,
                        "Expected both sides to be Int64, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TBool
            case TokenKind.GT =>
                if (!(l == StaticType.TInt64 && r == StaticType.TInt64)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.CMP_TYPE_MISMATCH,
                        "Expected both sides to be Int64, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TBool
            case TokenKind.GE =>
                if (!(l == StaticType.TInt64 && r == StaticType.TInt64)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.CMP_TYPE_MISMATCH,
                        "Expected both sides to be Int64, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TBool
            case TokenKind.EQUAL =>
                if (!(l == r)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.EQ_TYPE_MISMATCH,
                        "Expected both sides to be of the same type, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TBool

            case TokenKind.NOTEQ =>
                if (!(l == r)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.NEQ_TYPE_MISMATCH,
                        "Expected both sides to be of the same type, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TBool
            case TokenKind.AND =>
                if (!(l == StaticType.TBool && r == StaticType.TBool)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.AND_TYPE_MISMATCH,
                        "Expected both sides to be Bool, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TBool
            case TokenKind.OR =>
                if (!(l == StaticType.TBool && r == StaticType.TBool)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.OR_TYPE_MISMATCH,
                        "Expected both sides to be Bool, but got ${l.toString()} and ${r.toString()}",
                        b
                    )
                }
                StaticType.TBool
            case _ =>
                StaticType.TUnit
        }
    }

    public override func visit(f: FuncDecl): StaticType {
        let name = f.identifier.value

        // ========== 情况 1：类方法 / init ==========
        if (currentClassName.isSome()) {
            let cls = currentClassName.getOrThrow()
            let info = classes[cls]

            enterScope()

            // ---- 为方法注入 this ----
            currentScope()["this"] =
                TCVarInfo(StaticType.TClass(cls), false, false)
            let paramTypes = ArrayList<StaticType>()    

            // ---- 绑定参数 ----
            for (p in f.params.iterator()) {
                let tyNode =
                    if (p.declType.isSome()) {
                        p.declType.getOrThrow()
                    } else {
                        p.paramType
                    }

                let t = fromTypeNode(tyNode)
                paramTypes.add(t)
                currentScope()[p.identifier.value] =
                    TCVarInfo(t, false, false)
            }

            // ---- 如果是 init：检查字段初始化 ----
            let isInit = (f.keyword.value == "init")

            if (isInit) {
                info.methods["init"] =
                    StaticType.TFunc(paramTypes, StaticType.TUnit)
                currentFuncRetType = Option.Some(StaticType.TUnit)
                // 进入 init，执行块，收集赋值情况
                f.block.getOrThrow().traverse(this)

                // 检查所有字段是否被初始化
                for ((fieldName, inited) in info.fieldInitialized) {
                    if (!inited) {
                        throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.MEMBER_NOT_INITIALIZED_AFTER_INIT,
                            "field `${fieldName}` is not initialized after init()",
                            f
                        )
                    }
                }
                exitScope()
                return StaticType.TUnit
            }

            currentFuncRetType =
                Option.Some(fromTypeNode(f.declType.getOrThrow()))

            info.methods[name] =
                StaticType.TFunc(paramTypes, currentFuncRetType.getOrThrow())
            f.block.getOrThrow().traverse(this)

            currentFuncRetType = Option.None
            exitScope()
            return StaticType.TUnit
        }

        enterScope()
        let current = this.currentScope()
        // 1. 检查重复定义
        if (current.contains(name)) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.DUPLICATED_DEF,
                "Variable or function '${name}' is already defined in this scope",
                f
            )
        }

        // 2. 检查是否缺少返回类型
        if (f.declType.isNone()) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.FUNC_MISSING_RETURN_TYPE,
                "Function '${name}' must declare a return type",
                f
            )
        }
        currentFuncRetType =
            Option.Some(fromTypeNode(f.declType.getOrThrow()))

        let paramTypes = ArrayList<StaticType>()    
        // 绑定参数
        for (p in f.params.iterator()) {
            let t = fromTypeNode(p.declType.getOrThrow())
            currentScope()[p.identifier.value] =
                TCVarInfo(t, false, false)
            paramTypes.add(t)    
        }

        current[name] =
            TCVarInfo(
                StaticType.TFunc(paramTypes, currentFuncRetType.getOrThrow()),
                false,
                false
            )

        f.block.getOrThrow().traverse(this)
        
        currentFuncRetType = Option.None
        exitScope()

        return StaticType.TUnit
    }


    public override func visit(a: AssignExpr): StaticType {

        // ========= 1 先分析右值类型 =========
        let rhsType = a.right.traverse(this)

        // ========= 2 左侧必须是 RefExpr 或 MemberAccess =========
        match (a.left) {

            // ================== 变量赋值 ==================
            case r: RefExpr =>
                let name = r.identifier.value

                // —— 查找作用域中的变量 —— 
                var foundInfo: Option<TCVarInfo> = Option.None
                var foundScope: Option<HashMap<String, TCVarInfo>> = Option.None

                var i = scopes.size - 1
                while (i >= 0) {
                    let scope = scopes[i]
                    if (scope.contains(name)) {
                        foundInfo = Option.Some(scope.get(name).getOrThrow())
                        foundScope = Option.Some(scope)
                        break
                    }
                    i = i - 1
                }

                if (foundInfo.isNone()) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.UNDEFINED_VAR,
                        "Variable '${name}' is not defined.",
                        a
                    )
                }

                let info = foundInfo.getOrThrow()

                // —— 不允许给 let 变量赋值 —— 
                if (!info.isMutable) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.ASSIGN_IMMUT_VAR,
                        "Cannot assign to immutable variable '${name}'.",
                        a
                    )
                }

                // —— 类型必须一致 —— 
                if (!(rhsType == info.ty)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.ASSIGN_TYPE_MISMATCH,
                        "Expected type ${info.ty.toString()}, but got ${rhsType.toString()}",
                        a
                    )
                }

                // 赋值表达式本身类型为 Unit
                return StaticType.TUnit


            // ================== 成员赋值 ==================
            case ma: MemberAccess =>
                // 1) 推导 baseExpr 的类型
                let baseTy = ma.baseExpr.traverse(this)
                let fieldName = ma.field.value
                match (baseTy) {
                    case StaticType.TClass(clsName) =>
                        if (!classes.contains(clsName)) {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.UNDEFINED_CLASS,
                                "Class '${clsName}' is not defined.",
                                ma
                            )
                        }

                        let info = classes[clsName]

                        if (!info.fields.contains(fieldName)) {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.UNDEFINED_MEMBER,
                                "Field '${fieldName}' is not defined in class '${clsName}'.",
                                ma
                            )
                        }else{
                            if (!info.fieldInitialized[fieldName]) {
                                throw CjcjRuntimeErrorWithLocation(
                                    ErrorCode.UNINITIALIZED_MEMBER,
                                    "Field '${fieldName}' may be uninitialized.",
                                    ma
                                )
                            }
                        }

                        let fieldTy = info.fields[fieldName]

                        // 类型检查：rhs 必须是字段类型
                        if (!isSubtype(rhsType, fieldTy)) {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.ASSIGN_TYPE_MISMATCH,
                                "Expected type ${fieldTy.toString()}, but got ${rhsType.toString()}",
                                ma
                            )
                        }
                        return StaticType.TUnit

                    // ======== Option 解包对象后赋值 ========
                    case StaticType.TOption(innerTy) =>
                        match (innerTy) {
                            case StaticType.TClass(clsName) =>
                                if (!classes.contains(clsName)) {
                                    throw CjcjRuntimeErrorWithLocation(
                                        ErrorCode.UNDEFINED_CLASS,
                                        "Class '${clsName}' is not defined.",
                                        ma
                                    )
                                }

                                let info = classes[clsName]
                                if (!info.fields.contains(fieldName)) {
                                    throw CjcjRuntimeErrorWithLocation(
                                        ErrorCode.UNDEFINED_MEMBER,
                                        "Field '${fieldName}' is not defined in class '${clsName}'.",
                                        ma
                                    )
                                }

                                let fieldTy = info.fields[fieldName]

                                if (!isSubtype(rhsType, fieldTy)) {
                                    throw CjcjRuntimeErrorWithLocation(
                                        ErrorCode.ASSIGN_TYPE_MISMATCH,
                                        "Expected type ${fieldTy.toString()}, but got ${rhsType.toString()}",
                                        ma
                                    )
                                }

                                return StaticType.TUnit

                            case _ =>
                                throw CjcjRuntimeErrorWithLocation(
                                    ErrorCode.MEMBER_ACCESS_NON_OBJECT,
                                    "Attempting to assign to a member of a non-object Option.",
                                    ma
                                )
                        }



                     case r: RefExpr =>
                        if (r.identifier.value == "this" && currentClassName.isSome() && currentFuncRetType.isSome()) {
                            let cls = currentClassName.getOrThrow()
                            let info = classes[cls]

                            if (info.fieldInitialized.contains(ma.field.value)) {
                                info.fieldInitialized[ma.field.value] = true
                            }
                        }
                    // ======== 其它非法情况 ========
                    case _ =>
                        throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.MEMBER_ACCESS_NON_OBJECT,
                            "Left side of assignment is not an object.",
                            ma
                        )


                }

            // ================== 其它非法左值 ==================
            case _ =>
                throw CjcjRuntimeErrorWithLocation(
                    ErrorCode.ASSIGN_TYPE_MISMATCH,
                    "Left side of assignment must be a variable or member access.",
                    a
                )
        }

        return StaticType.TUnit
    }


    public override func visit(body: Body): StaticType {
        for (d in body.decls.iterator()) {
            d.traverse(this)
        }
        return StaticType.TUnit
    }

    public override func visit(arg: Argument): StaticType {
        return arg.expr.traverse(this)
    }

    public override func visit(m: MainDecl): StaticType {
        enterScope()

        if (m.param.isSome()) {
            let p = m.param.getOrThrow()
            currentScope()[p.identifier.value] =
                TCVarInfo(fromTypeNode(p.declType.getOrThrow()), false, false)
        }

        m.block.traverse(this)

        exitScope()
        return StaticType.TUnit
    }


    public override func visit(b: Block): StaticType {
        enterScope()
        var last = StaticType.TUnit
        for (n in b.nodes.iterator()) {
            last = n.traverse(this)
        }
        exitScope()
        last
    }

    public override func visit(i: IfExpr): StaticType {
        let cond = i.condition.traverse(this)
        expectBool(cond, i, ErrorCode.IF_TYPE_MISMATCH)

        let t1 = i.ifBlock.traverse(this)
        let t2 = i.elseBranch.traverse(this)

        match (StaticType.join(t1, t2)) {
            case Option.Some(t) => t
            case Option.None => StaticType.TUnit
        }
    }

    public override func visit(w: WhileExpr): StaticType {
        let cond = w.condition.traverse(this)
        expectBool(cond, w, ErrorCode.WHILE_TYPE_MISMATCH)

        loopDepth = loopDepth + 1
        _ = w.block.traverse(this)
        loopDepth = loopDepth - 1

        StaticType.TUnit
    }


    public override func visit(r: ReturnExpr): StaticType {
        let t =
            if (r.expr.isSome()) {
                r.expr.getOrThrow().traverse(this)
            } else {
                StaticType.TUnit
            }

        if (currentFuncRetType.isSome()) {
            let expected = currentFuncRetType.getOrThrow()
            if (!isSubtype(t, expected)) {
                throw CjcjRuntimeErrorWithLocation(
                    ErrorCode.FUNC_RETURN_TYPE_MISMATCH,
                    "Expected return type ${expected.toString()}, but got ${t.toString()}",
                    r
                )
            }
        }
        StaticType.TBottom
    }

    public override func visit(j: JumpExpr): StaticType {
        if (loopDepth == 0) {
            match (j.keyword.kind) {
                case TokenKind.BREAK =>
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.BREAK_OUTSIDE_LOOP,
                        "Break statement is outside of a loop.",
                        j
                    )
                case TokenKind.CONTINUE =>
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.CONTINUE_OUTSIDE_LOOP,
                        "Continue statement is outside of a loop.",
                        j
                    )
                case _ => ()
            }
        }
        StaticType.TBottom
    }

    public override func visit(decl: VarDecl): StaticType {
        let name = decl.identifier.value
        let scope = currentScope()

        if (scope.contains(name)) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.DUPLICATED_DEF,
                "Variable '${name}' is already defined in the current scope.",
                decl
            )
        }

        let isMutable = (decl.keyword.kind == TokenKind.VAR)
        let isGlobal = (scopes.size == 1)

        if (isGlobal && decl.initializer.isNone()) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.GLOBAL_NO_INITIALIZER,
                "Global variable '${name}' must have an initializer.",
                decl
            )
        }

        let initType =
            if (decl.initializer.isSome()) {
                decl.initializer.getOrThrow().traverse(this)
            } else {
                StaticType.TBottom   // 表示“尚未初始化”
            }

        let varType: StaticType =
            if (decl.declType.isSome()) {
                let declaredType = fromTypeNode(decl.declType.getOrThrow())

                if (decl.initializer.isSome() && !isSubtype(initType, declaredType)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.DEF_TYPE_MISMATCH,
                        "Expected type ${declaredType.toString()}, but got ${initType.toString()}",
                        decl
                    )
                }

                declaredType
            } else {
                if (decl.initializer.isNone()) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.DEF_TYPE_MISMATCH,
                        "Type annotation is required when there is no initializer.",
                        decl
                    )
                }
                initType
            }

        scope[name] = TCVarInfo(
            varType,
            isMutable,
            isGlobal
        )

        return StaticType.TUnit
    }



    public override func visit(call: CallExpr): StaticType {

        // =============================
        // 1️  special case: Class constructor call
        //  callee is a RefExpr AND its name is a class
        // =============================
        match (call.callee) {
            case r: RefExpr =>
                let cname = r.identifier.value
                if (classes.contains(cname)) {
                    let info = classes[cname]
                    // ---- has init() ----
                    if (info.methods.contains("init")) {
                        match (info.methods["init"]) {
                            case StaticType.TFunc(params, _) =>
                                if (params.size != call.arguments.size) {
                                    throw CjcjRuntimeErrorWithLocation(
                                        ErrorCode.CALL_ARG_COUNT_MISMATCH,
                                        "Constructor of '${cname}' expects ${params.size} args, got ${call.arguments.size}",
                                        call
                                    )
                                }

                                for (i in 0 .. params.size - 1) {
                                    let argTy = call.arguments[i].traverse(this)
                                    if (!isSubtype(argTy, params[i])) {
                                        throw CjcjRuntimeErrorWithLocation(
                                            ErrorCode.CALL_ARG_TYPE_MISMATCH,
                                            "Constructor param ${i} of '${cname}' expects ${params[i].toString()}, got ${argTy.toString()}",
                                            call
                                        )
                                    }
                                }

                            case _ => ()
                        }
                    } else {
                        if (call.arguments.size != 0) {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.CALL_ARG_COUNT_MISMATCH,
                                "Class '${cname}' has no constructor but ${call.arguments.size} arguments provided",
                                call
                            )
                        }
                    }

                    // constructor call returns the class type
                    return StaticType.TClass(cname)
                }

            case _ => ()
        }

        let calleeTy = call.callee.traverse(this)

        match (calleeTy) {
            case StaticType.TFunc(params, ret) => 
                if (params.size != call.arguments.size) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.CALL_ARG_COUNT_MISMATCH,
                        "Expected ${params.size} arguments, but got ${call.arguments.size}.",
                        call
                    )
                }
                for (i in 0 .. params.size - 1) {
                    let argTy = call.arguments[i].traverse(this)
                    if (!isSubtype(argTy, params[i])) {
                        throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.CALL_ARG_TYPE_MISMATCH,
                            "Expected argument ${i} to be of type ${params[i].toString()}, but got ${argTy.toString()}.",
                            call
                        )
                    }
                }
                ret
            

            case StaticType.TOption(inner) => 
                match (call.callee) {
                    case ma: MemberAccess =>
                        if (ma.field.value == "getOrThrow") {
                            inner
                        } else {
                            throw CjcjRuntimeErrorWithLocation(
                                ErrorCode.UNDEFINED_MEMBER,
                                "Member '${ma.field.value}' is not defined for Option type.",
                                ma
                            )
                        }
                    case _ =>
                        throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.CALLEE_NOT_FUNCTION,
                            "Attempting to call a non-function value.",
                            call
                        )
                }
            

            case _ =>
                throw CjcjRuntimeErrorWithLocation(
                    ErrorCode.CALLEE_NOT_FUNCTION,
                    "Attempting to call a non-function value.",
                    call
                )
        }
    }

    public override func visit(ma: MemberAccess): StaticType {
        let base = ma.baseExpr.traverse(this)
        let name = ma.field.value

        match (base) {
            case StaticType.TClass(cls) => 
                if (!classes.contains(cls)) {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.UNDEFINED_CLASS,
                        "Class '${cls}' is not defined.",
                        ma
                    )
                }
                let info = classes[cls]
                if (info.fields.contains(name)) {
                    return info.fields[name]
                } else if (info.methods.contains(name)) {
                    return info.methods[name]
                } else {
                    throw CjcjRuntimeErrorWithLocation(
                        ErrorCode.UNDEFINED_MEMBER,
                        "Member '${name}' is not defined in class '${cls}'.",
                        ma
                    )
                }
            
            case StaticType.TOption(inner) => 
                match (name) {
                    case "isSome" => StaticType.TBool 
                    case "isNone" => StaticType.TBool
                    case "getOrThrow" => inner
                    case _ => 
                        throw CjcjRuntimeErrorWithLocation(
                            ErrorCode.UNDEFINED_MEMBER,
                            "Member '${name}' is not defined for Option type.",
                            ma
                        )
                }

            case _ =>
                throw CjcjRuntimeErrorWithLocation(
                    ErrorCode.MEMBER_ACCESS_NON_OBJECT,
                    "Base expression is not an object.",
                    ma
                )
        }
    }

    public override func visit(c: ClassDecl): StaticType {

        currentClassName = Option.Some(c.identifier.value)
        enterScope()

        currentScope()["this"] =
            TCVarInfo(StaticType.TClass(c.identifier.value), false, false)

        currentClass = Option.Some(c.identifier.value)
        c.body.traverse(this)     // 再检查方法体
        currentClass = Option.None

        exitScope()
        currentClassName = Option.None

        return StaticType.TUnit
    }


    public override func visit(ts: ThisSuperExpr): StaticType {
        if (currentClassName.isNone()) {
            throw CjcjRuntimeErrorWithLocation(
                ErrorCode.UNDEFINED_CLASS,
                "`this` used outside class",
                ts
            )
        }
        return StaticType.TClass(currentClassName.getOrThrow())
    }

}