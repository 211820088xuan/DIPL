package cjcj.executor

import cjcj.visitor.*
import std.deriving.Derive

@Derive[ToString]
public enum ErrorCode {
    | ADD_TYPE_MISMATCH // 加法两侧类型不受支持。
    | ADD_OVERFLOW // 整数加法结果超出 `Int64` 表示范围。
    | SUB_TYPE_MISMATCH // 减法两侧类型不受支持。
    | SUB_OVERFLOW // 整数减法结果超出 `Int64` 表示范围。
    | MUL_TYPE_MISMATCH // 乘法两侧类型不受支持。
    | MUL_OVERFLOW // 整数乘法结果超出 `Int64` 表示范围。
    | DIV_TYPE_MISMATCH // 除法两侧类型不受支持。
    | DIV_BY_ZERO // 整数除法的除数为 0。
    | MOD_TYPE_MISMATCH // 取余两侧类型不受支持。
    | MOD_BY_ZERO // 取余运算的除数为 0。
    | EXP_NEGATIVE_POWER // 指数为负数的幂运算不被支持。
    | EXP_OVERFLOW // 幂运算结果超出 `Int64` 表示范围。
    | EXP_TYPE_MISMATCH // 幂运算两侧类型不受支持。
    | CMP_TYPE_MISMATCH // 比较运算两侧的类型不受支持。
    | EQ_TYPE_MISMATCH // 比较两个不一样的类型。
    | NEQ_TYPE_MISMATCH // 比较两个不一样的类型。
    | AND_TYPE_MISMATCH // 在计算中遇到逻辑与的任一操作数不是 `Bool`。
    | OR_TYPE_MISMATCH // 在计算中遇到逻辑或的任一操作数不是 `Bool`。
    | NOT_TYPE_MISMATCH // 逻辑非的操作数不是 `Bool`。
    | NEG_TYPE_MISMATCH // 一元取负的操作数不是 `Int64`。
    | NEG_OVERFLOW // 一元取负运算发生溢出。
    | IF_TYPE_MISMATCH // if 条件表达式的结果不是 `Bool`。
    | WHILE_TYPE_MISMATCH // while 条件表达式的结果不是 `Bool`。
    | BREAK_OUTSIDE_LOOP // 在非循环体内使用 `break`。
    | CONTINUE_OUTSIDE_LOOP // 在非循环体内使用 `continue`.
    | ASSIGN_IMMUT_VAR // 试图给 `let` 定义的不可变变量赋值。
    | ASSIGN_TYPE_MISMATCH // 试图给变量赋值成不同的类型。
    | UNDEFINED_VAR // 试图使用未定义的变量。
    | DUPLICATED_DEF // 试图在同一静态作用域内定义同名变量。
    | DEF_TYPE_MISMATCH // 变量定义时，赋值的类型与声明的类型不匹配。
    | UNINITIALIZED_VAR // 试图读取未初始化的变量的值。
    | GLOBAL_NO_INITIALIZER // 全局变量定义缺少初始化表达式。
    | FUNC_MISSING_RETURN_TYPE // 函数定义中省略了返回类型。
    | FUNC_MISSING_BODY // 函数定义中缺少函数体。
    | CALLEE_NOT_FUNCTION // 试图调用一个非函数值。
    | CALL_ARG_COUNT_MISMATCH // 函数调用时实参个数与形参个数不匹配。
    | CALL_ARG_TYPE_MISMATCH // 函数调用时实参类型与形参类型不匹配。
    | FUNC_USE_MUTABLE_NONLOCAL // 试图访问可变非局部变量。
    | FUNC_RETURN_TYPE_MISMATCH // 函数返回值类型与声明的返回类型不匹配。
    //ADDED ERRORS
    | ASSIGN_IMMUT_DECL // 试图给不可变实体赋值。
    | THIS_SUPER_OUTSIDE_CLASS // 在类定义外使用 this 或 super。
    | CLASS_MISSING_MEMBER // 类定义中缺少成员变量或方法。
    | UNDEFINED_MEMBER // 试图访问未定义的成员变量或方法。
    | UNINITIALIZED_MEMBER // 试图访问未初始化的成员变量。
    | MEMBER_NOT_INITIALIZED_AFTER_INIT // init 方法执行完后，成员变量未全部初始化。
    | UNDEFINED_CLASS // 试图实例化一个未定义的类。
    | OPTION_IS_NONE // 试图访问一个值为 None 的 Option。
    | OPTION_IS_SOME // 试图访问一个值为 Some 的 Option。
    | MEMBER_ACCESS_NON_OBJECT // 试图在非对象值上访问成员。
    | MEMBER_ASSIGN_NON_OBJECT // 试图在非对象值上赋值成员。
    | OPTION_METHOD_ON_NON_OPTION // 试图在非 Option 类型上调用 Option 方法。
    | OPTION_UNWRAP_NONE // 试图 unwrap 一个值为 None 的 Option。
    | OPTION_GETORTHROW_ERRMSG_NOT_STRING // 试图用非字符串作为 getOrThrow 的错误信息。
    | CONSTRUCTOR_RETURN_TYPE
    | FIELD_INIT_TYPE_MISMATCH // 成员变量初始化时类型不匹配。
    | UNSUPPORTED_DECL_IN_CLASS
    | NOT_A_FUNCTION // 试图将非函数类型作为函数使用。
    | INVALID_THIS // 仅支持使用 'this'，暂不支持 'super'。
}

public class CjcjRuntimeErrorWithLocation <: Exception {
    CjcjRuntimeErrorWithLocation(
        public let code: ErrorCode,
        public let extraMessage: String,
        public let fromWhere: Node
    ) {}

    public override func toString(): String {
        "Error at line ${getPosition(fromWhere).line}: [${code.toString()[10..]}]: ${extraMessage}" 
    }
}
