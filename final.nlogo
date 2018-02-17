extensions [table] ;;use the hash table data structure

breed [persons person] ;;students and professors
breed [DAs DA] ;;department agents
breed [courses course]
undirected-link-breed [course_course_links course_course_link] ;;courses are linked, and the weight of each link is the sum of priorities of person agents in common
undirected-link-breed [person_DA_links person_DA_link] ;;persons with a department_id are linked to DAs with the same department_id

globals [
  ;;variables for storing data extracted from file
  courses_info
  professors_courses_info
  students_courses_info

  num_departments
  num_courses
  num_students
  num_professors

  total_dept_clashes

  temperature ;;for metropolis acceptance criterion
]

persons-own [
  department_id

  priority
  own_dept_courses
  other_dept_courses

  timetable ;;course -> which time slot it falls in
  slot_hits ;;slot -> number of courses in that slot

  clashes
]

DAs-own [
  department_id
  timetable
  slot_hits
  clashes
]

courses-own [
  department_id
  course_id
  degree ;;number of persons in common with others
]

course_course_links-own[
  weight
]

to setup
  __clear-all-and-reset-ticks

  set courses_info []
  set professors_courses_info []
  set students_courses_info []

  ;;load data from files
  file-open "courses.txt"
  set num_departments file-read
  set num_courses file-read
  while [ not file-at-end? ]
  [
    set courses_info lput (file-read) courses_info
  ]
  file-close

  file-open "professors_and_courses.txt"
  set num_professors file-read
  while [ not file-at-end? ]
  [
    set professors_courses_info lput (file-read) professors_courses_info
  ]
  file-close

  file-open "students_and_courses.txt"
  set num_students file-read
  while [ not file-at-end? ]
  [
    set students_courses_info lput (file-read) students_courses_info
  ]
  file-close

  ;;create agents for courses
  foreach courses_info[
    x ->
    create-courses 1 [
      set shape "circle"
      setxy random-xcor int(0.6 * max-pycor + 0.4 * random-ycor)
      set department_id (item 1 x)
      set course_id (item 0 x)
    ]
  ]

  ;;create agents for students
  foreach students_courses_info[
    x ->
    create-persons 1 [
      set priority 1
      set shape "person"
      set color green
      setxy random-xcor random-ycor / 2
      set department_id item 0 x
      set own_dept_courses item 1 x
      set other_dept_courses item 2 x
      ;;data structure for slot hits (in order to calculate clashes)
      set slot_hits n-values total_time_slots [0]
      ;;data structure for timetable
      set timetable table:make
      set clashes 0
    ]
  ]

  ;;create agents for professors
  foreach professors_courses_info[
    x ->
    create-persons 1 [
      set priority prof_threshold_priority
      set shape "person"
      set color red
      setxy random-xcor random-ycor / 2
      set department_id item 0 x
      set own_dept_courses item 1 x
      set other_dept_courses item 2 x
      ;;data structure for slot hits (in order to calculate clashes)
      set slot_hits n-values total_time_slots [0]
      ;;data structure for timetable
      set timetable table:make
      set clashes 0
    ]
  ]

  ;;create DAs
  foreach ( range 1 (num_departments + 1) ) [
    x ->
    create-DAs 1 [
      set shape "box"
      setxy random-xcor random-ycor / 2
      set department_id x
      set color int ( department_id / num_departments * 139 )
      ;;slot hits
      set slot_hits n-values total_time_slots [0]
      ;;data structure for timetable
      set timetable table:make
      set clashes 0
    ]
  ]

  ;;create links between courses
  ask courses [
    create-course_course_links-with other courses
  ]

  ;;assign weights to the courses based on number of persons (students and professors) in common
  ask persons [
    let prior priority
    foreach sentence own_dept_courses other_dept_courses [
      x ->
      foreach sentence own_dept_courses other_dept_courses [
        y ->
        if y != x [
          ask course_course_link (item 0 [who] of courses with [course_id = x]) (item 0 [who] of courses with [course_id = y]) [
            set weight weight + prior
          ]
        ]
      ]
    ]
  ]

  ;;kill links with zero weight
  ask course_course_links with [weight = 0] [
    die
  ]

  ;;recolor links based on weight
  ask course_course_links [
    set color ( weight / (max [weight] of course_course_links) * 139 )
  ]

  ;;assign degree to each course (for largest degree heuristic)
  ask courses [
    set degree sum [weight] of my-course_course_links
  ]
  ask courses [
    set color int 60 + ( degree / (max [degree] of courses + 1) * 10)
  ]

  ;;setup initial timetable

  ;;generate random initial timetable, not respecting clashes, using Largest Degree heuristic

  let total_taken 0

  ask DAs [
    let did department_id
    let tt timetable
    let sh slot_hits

    ;;in decreasing order of degree
    foreach sort-by > sort-on [degree] courses with [department_id = did] [
      thecourse -> ask thecourse [
        ;;update slot hits
        let rval one-of range (length sh)
        set sh replace-item rval sh ( (item rval sh) + 1 )

        ;;update timetable
        table:put tt course_id rval ;;update timeslot the course has been assigned
      ]
    ]

    set slot_hits sh
    set timetable tt

    ;;initialize personal timetables
    init_personal_timetables department_id timetable slot_hits
  ]

  update_total_dept_clashes

  set temperature start_temperature

  setup-plots
  update-plots
end


to go
  ;;simulated annealing approach to obtain timetable minimizing clashes
  ;;i.e: search the solution space using the Metropolis Monte Carlo algorithm, adjust temperature parameter as per the cooling schedule

  ask DAs [
    let old_clashes clashes

    ifelse random-float 1 < 0.5 [
      ;;move 1: move a random course to a new time slot
      let did department_id
      let course_moved one-of courses with [ department_id = did ]
      let old_slot table:get timetable ([course_id] of course_moved)
      let new_slot one-of range total_time_slots
      let sh slot_hits
      let tt timetable

      ask course_moved [
        set sh replace-item old_slot sh ( (item old_slot sh) - 1 ) ;;course has moved
        set sh replace-item new_slot sh ( (item new_slot sh) + 1 ) ;;course has moved

        ;;update timetable
        table:put tt course_id new_slot ;;update timeslot the course has been assigned
      ]

      set timetable tt
      set slot_hits sh

      ;;It is not efficient to re-construct each person's personal timetable information for just one update.
      ;;However, due to the small size of the test instances, we can get away with this - for now...
      ;;TODO: add a more efficient update function
      init_personal_timetables department_id timetable slot_hits
      update_total_dept_clashes


      ;;if the Metropolis criterion isn't satisfied
      if (clashes > old_clashes and random-float 1 > ( exp ( old_clashes - clashes ) / temperature ) ) [
        show "Move rejected"
        ;;undo the move
        ask course_moved [
          ;;update slot hits
          set sh replace-item old_slot sh ( (item old_slot sh) + 1 ) ;;course has moved back
          set sh replace-item new_slot sh ( (item new_slot sh) - 1 ) ;;course has moved back

         ;;update timetable
          table:put tt course_id old_slot ;;update timeslot the course has been assigned
        ]

        set timetable tt
        set slot_hits sh

        init_personal_timetables department_id timetable slot_hits
        update_total_dept_clashes
      ]

    ] [
      ;;move 2: swap two random courses' time slots
      let did department_id
      if ( count courses with [ department_id = did ] ) >= 2 [
        let courses_swapped [course_id] of ( n-of 2 courses with [ department_id = did ] )
        let c1 item 0 courses_swapped
        let c2 item 1 courses_swapped
        let c1slot table:get timetable c1
        let c2slot table:get timetable c2
        let sh slot_hits
        let tt timetable

        ;;make swap
        ask courses with [course_id = c1] [
          ;;update timetable
          table:put tt course_id c2slot ;;update timeslot
        ]

        ask courses with [course_id = c2] [
          ;;update timetable
          table:put tt course_id c1slot ;;update timeslot
        ]

        set timetable tt
        set slot_hits sh

        ;;It is not efficient to re-construct each person's personal timetable information for just one update.
        ;;However, due to the small size of the test instances, we can get away with this - for now...
        ;;TODO: add a more efficient update function
        init_personal_timetables department_id timetable slot_hits
        update_total_dept_clashes


        ;;if the Metropolis criterion isn't satisfied
        if (clashes > old_clashes and random-float 1 > ( exp ( old_clashes - clashes ) / temperature ) ) [
          show "Swap rejected"
          ;;undo swap
          ask courses with [course_id = c1] [
            ;;update timetable
            table:put tt course_id c1slot ;;update timeslot
          ]

          ask courses with [course_id = c2] [
            ;;update timetable
            table:put tt course_id c2slot ;;update timeslot
          ]

          set timetable tt
          set slot_hits sh

          init_personal_timetables department_id timetable slot_hits
          update_total_dept_clashes
        ]

      ]

    ]

  ]

  if temperature > 0.00001 [
    set temperature max list (temperature - cooling_rate) 0.00001
  ]

  tick;
end

to showtimetable
  ask DAs [
    show word "For department " department_id
    show timetable
    show word "Clashes: " clashes
  ]
end

to init_personal_timetables [id tt sh]
  ask DAs with [ department_id = id ] [
    ask persons with [ department_id = id ] [

      let mytimetable timetable
      let myslot_hits n-values total_time_slots [0]

      foreach ([course_id] of courses with [department_id = id ] ) [
        cur_course ->

        if member? cur_course own_dept_courses [
          ;;update individual timetable
          let timeslot table:get tt cur_course
          table:put mytimetable cur_course timeslot

          ;;update slot hits
          set myslot_hits replace-item timeslot myslot_hits ( (item timeslot myslot_hits) + 1 )
        ]
      ]

      set timetable mytimetable
      set slot_hits myslot_hits
    ]
  ]
end

to update_total_dept_clashes
  let tot 0
  ask DAs [
    set clashes getclashes department_id timetable slot_hits
    set tot tot + clashes
  ]
  set total_dept_clashes tot
end

to-report getclashes [id tt sh]
  let calc_clashes 0

  ask DAs with [ department_id = id ] [
    ask persons with [ department_id = id ] [
      foreach range total_time_slots [
        slot ->
        if item slot slot_hits > 1 [
          set calc_clashes calc_clashes + priority ;;priority of self
        ]
      ]
    ]
  ]
  report calc_clashes
end
@#$#@#$#@
GRAPHICS-WINDOW
256
17
904
666
-1
-1
19.4
1
10
1
1
1
0
0
0
1
0
32
0
32
0
0
1
ticks
30.0

BUTTON
20
255
101
289
Setup 
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
22
99
242
132
cooling_rate
cooling_rate
0
1
0.92
0.01
1
NIL
HORIZONTAL

SLIDER
22
18
241
51
prof_threshold_priority
prof_threshold_priority
0
100
77.0
1
1
NIL
HORIZONTAL

SLIDER
21
167
239
200
total_time_slots
total_time_slots
0
336
3.0
1
1
NIL
HORIZONTAL

TEXTBOX
22
208
138
238
(Number of time slots per week)
12
0.0
1

TEXTBOX
22
135
244
155
Parameters for Simulated Annealing
12
0.0
1

MONITOR
918
70
1058
115
Number of courses
num_courses
17
1
11

MONITOR
918
120
1063
165
Number of students
num_students
17
1
11

MONITOR
918
170
1078
215
Number of professors
num_professors
17
1
11

MONITOR
918
19
1090
64
Number of departments
num_departments
17
1
11

BUTTON
20
367
163
401
Print Timetable
showtimetable
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
918
225
1034
269
- Lighter courses have higher degree
12
0.0
1

PLOT
1108
20
1438
234
Clashes
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot total_dept_clashes"

BUTTON
20
309
113
343
Optimize
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
22
59
242
93
start_temperature
start_temperature
0
1000
270.0
0.5
1
NIL
HORIZONTAL

PLOT
1107
238
1439
453
Temperature (Annealing)
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot temperature"

@#$#@#$#@
## WHAT IS IT?

This is a model for timetable scheduling, where different breeds of agents play the role of different stake-holders in the problem, and simulate the negotiation that normally occurs in offline course-scheduling to arrive to an optimal schedule.

In this model, I make the following assumptions:

- All lectures are of the same time interval
- All lectures are of the same type
- There is no bottleneck in terms of rooms (we do not need to account for rooms during scheduling - just the time slots)

## HOW IT WORKS

- A course is decomposed into 'events' - each lecture or tutorial is an event.
- Each day is decomposed into a certain number of time slots.
- Each event is thought of as a meeting involving a professor and students. Hence, professors and students are treated as the same type of agent. However, they are given different priorities. The priority of a student is 1, and the priority of a professor can be preset.
- Each course belongs to a department. Some courses (electives) are shared between departments.

STAGE 1:
At first, each department prepares its own timetable, ignoring the shared courses (electives), using Department Agents 

STAGE 2:
Next, the departments communicate with a Univeral Timetable Agent, to try and produce an optimal timetable.

This NetLogo code implements Stage 1. Stage 2 is future work.

Approach for Stage 1:

- Generate a random allotment, sorting by the largest degree (sum of weights of persons which that course shares)
- Begin search for optimum allotment using simulated annealing to converge to the global optimum

Approach for Stage 2:

- After each department has generated its timetable, Department Agents negotiate with Universal Timetable Agent to produce final output.

## THINGS TO TRY

Play around with:

- The priority of professor
- Simulated annealing start temperature
- Simulated annealing cooling rate (decrease in temperature per tick)

## EXTENDING THE MODEL

The model can be extended to impose additional constraints:

- Too many events of the same course should not fall together on a single day (soft constraint => less penalty)
- Events of type 'lab' should fall together in a contiguous interval (hard constraint => high penalty)

## REFERENCES

(To be added)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.2
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
