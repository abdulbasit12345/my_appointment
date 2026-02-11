import 'package:flutter/material.dart';


class GetTextFormFiled extends StatelessWidget {
  final TextEditingController controller;
  final String hintName;
  final String lableText;
  final IconData icon;
  final bool isObscureText;
  final TextInputType inputType;
  final bool isEnable;
  final FocusNode focusNode;


   GetTextFormFiled({
    super.key,
    required this.controller,
    required this.hintName,
    required this.icon,
     required this.lableText,
    this.isObscureText= false,
    this.inputType= TextInputType.text,
    this.isEnable = true,
     required this.focusNode
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10,vertical: 5),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          //color: AppColors.appColor,
          borderRadius: BorderRadius.circular(50),
        ),
        padding: const EdgeInsets.only(left: 8,right: 8),
        child: Center(
          child: TextFormField(
            controller: controller,
            obscureText:isObscureText ,
            enabled: isEnable,
            keyboardType: inputType,
            focusNode: focusNode,
            validator: (value){
              if(value!.isEmpty){
                return 'Please Enter$hintName';
              }
              return null;
            },
            decoration: InputDecoration(
              //border: InputBorder.none,

              prefixIcon: Icon(icon,color: Colors.yellow,),
              hintText: hintName,
               labelText: lableText,
              labelStyle: const TextStyle(color: Colors.black),
              //   fillColor: Colors.grey.shade100,
              fillColor: Colors.transparent,
              //orange.shade300.withOpacity(0.8),
              filled: true,
            ),
          ),
        ),
      ),
    );
  }
}
