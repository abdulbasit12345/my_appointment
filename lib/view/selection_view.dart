
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../res/color.dart';
import 'authentication/doctor_auth/doctor_login_view.dart';
import 'authentication/patient_auth/patient_lgoin_view.dart';

class SelectionView extends StatefulWidget {
  const SelectionView({super.key});

  @override
  State<SelectionView> createState() => _SelectionViewState();
}

class _SelectionViewState extends State<SelectionView> {
  @override
  Widget build(BuildContext context) {

    double w = MediaQuery.of(context).size.width;
    double h = MediaQuery.of(context).size.height;
    return Scaffold(
      //backgroundColor: AppColors.appColor,
      body: Column(
        children: [
          Expanded(
            flex: 40,
            child: Container(
              //color: AppColors.appColor,
              color: Colors.grey.shade200,
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                        borderRadius: BorderRadius.only(
                          bottomRight: Radius.circular(650),
                          bottomLeft: Radius.circular(100),
                        ),
                        color: Colors.blueAccent,
                        // gradient: LinearGradient(
                        //   end: Alignment.topLeft,
                        //   begin: Alignment.bottomCenter,
                        //   colors: [
                        //     Colors.blue.shade200.withOpacity(1),
                        //     //  Colors.blue.shade600.withOpacity(1),
                        //     //Colors.blue.shade600.withOpacity(1),
                        //     Colors.blue.shade200.withOpacity(1),
                        //   ],
                        // )
                    ),
                  ),
                  const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add,
                            color: AppColors.redColor,
                            size: 60,
                          ),
                          Text(
                            'Medical',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 35,
                                fontWeight: FontWeight.w600),
                          ),
                          SizedBox(
                            width: 60,
                          )
                        ],
                      ),
                      SizedBox(
                        height: 30,
                      ),
                      Text(
                        'Welcome',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        height: 130,
                        width: 120,
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(650),
                              bottomLeft:  Radius.circular(100)
                          ),),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
              flex: 60,
              child: Container(
                width: w,
                //color: AppColors.appColor,
                color: Colors.grey.shade200,
                child: Column(children: [
                  const Text(
                    'Continue As',
                    style: TextStyle(
                        color: AppColors.blackColor,
                        fontSize: 30,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 30,),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(

                        onTap: (){
                         // Navigator.pushNamed(context, RoutesName.doctor_login);
                          Navigator.of(context).pushReplacement(CupertinoPageRoute(builder: (context) => const DoctorLoginView()));
                         // Navigator.pushReplacement(context, MaterialPageRoute(builder: (context)=> DoctorLoginView()));
                        },
                        child: Column(
                          children: [

                            Container(
                              height: h * 0.2,
                              width: w * 0.44,
                              //margin: EdgeInsets.all(6),
                              //padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent,
                                borderRadius: BorderRadius.circular(1000),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(35.0),
                                child: Image.asset('assets/doctor.png',color: Colors.white,alignment: Alignment.center,fit: BoxFit.cover),
                              ),
                            ),
                            const Text(
                              'Doctor',
                              style: TextStyle(
                                  color:AppColors.blackColor,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold),
                            ),

                          ],
                        ),
                      ),
                      //Patient work
                      GestureDetector(
                        onTap: (){
                          //Navigator.pushNamed(context, RoutesName.patient_login);
                          Navigator.of(context).pushReplacement(CupertinoPageRoute(builder: (context) => const PatientLoginView()));
                          //Navigator.pushReplacement(context, MaterialPageRoute(builder: (context)=> PatientLoginView()));
                        },
                        child: Column(
                          children: [
                            Container(
                              height: h * 0.2,
                              width: w * 0.44,
                              //margin: EdgeInsets.all(6),
                              //padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent,
                                borderRadius: BorderRadius.circular(1000),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(35.0),
                                child: Image.asset('assets/patient.png',color: Colors.white,alignment: Alignment.center,fit: BoxFit.cover),
                              ),
                            ),
                            const Text(
                              'Patient',
                              style: TextStyle(
                                  color: AppColors.blackColor,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold),
                            ),

                          ],
                        ),
                      ),

                    ],)
                ]),
              )),
        ],
      ),
    );
  }
}
