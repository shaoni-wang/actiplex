breed [individuals individual]
undirected-link-breed [connections connection]  ; Represents connections between individuals (citizens)

globals [
  who-opinion             ; Monitors a specific agent's opinion
  strength-variation      ; Variation in strength, controls movement reinforcement
  oppo-value              ; Count of agents with negative opinions
  suppo-value             ; Count of agents with positive opinions
  neutral-value           ; Count of agents with neutral opinions
  initial-percentage      ; Initial opinion distribution percentage
  percentage              ; Current percentage of opinion distribution
  reconcile?              ; Flag for enabling/disabling reconciliation (toggle in interface)
  reinforcement           ; Reinforcement of the opinions
]

connections-own [
  link-strength           ; Frequency/strength of interaction between an individual and its connections
]

individuals-own [
  distance-neigh          ; List storing distances to all neighbors
  behaviour               ; Behavior type: either "support" or "oppose"
  initial-position        ; Initial opinion or position of the individual
  opinion                 ; Current opinion or strength of the individual's stance
  satisfaction            ; Overall satisfaction of the individual
  social-satisfaction     ; Satisfaction derived from social connections
  non-social-satisfaction ; Satisfaction derived from personal values or experiences
  social-importance       ; Weight/importance of social satisfaction
  non-social-importance   ; Weight/importance of non-social satisfaction
  latitude-of-acceptance  ; Social judgment theory: range of acceptable opinions
  latitude-of-rejectance  ; Social judgment theory: range of rejected opinions
  non-commitment          ; Level of emotional involvement or openness to change
]

;;;;;;;;;;;;;;;;;;
;;;;;;Setup;;;;;;;
;;;;;;;;;;;;;;;;;;
to setup
  clear-all
  reset-ticks
  resize-world 0 200 0 200
  ;random-seed 100

  ask patches [set pcolor white]
  set who-opinion 0
  set reconcile? false
  set reinforcement 0.01  ; Low reinforcement for low speed of opinion changing

  create-individuals num-agents [
    setxy random-xcor random-ycor
    set non-commitment (1 - level-of-involvement)  ; Lower emotion means higher non-commitment
    set latitude-of-acceptance 1                 ; Determines openness/acceptance
    set latitude-of-rejectance (latitude-of-acceptance + non-commitment)
    set size 9
  ]

  setup-networks       ; Establish connections
  setup-individuals    ; Initialize individual properties
end

to setup-networks      ; Establish social links based on average social connections
  while [count connections < ((avg-connections * num-agents) / 2)] [
    ask one-of individuals [
      let target min-one-of (other individuals with [not connection-neighbor? myself]) [distance myself]
      if target != nobody [create-connection-with target]
    ]
  ]

  ; Configure connection properties
  ask connections [
    set color 8.5
    set link-strength 0
  ]

  ; Show or hide connections based on the 'show-links?' flag
  ifelse show-links?
    [ ask connections [set hidden? false] ]
    [ ask connections [set hidden? true] ]
end

to setup-individuals
  ask individuals [
    set non-social-satisfaction random-normal-trunc 0 1 -1 1  ; Randomized satisfaction (-1 to 1)
    set opinion non-social-satisfaction                       ; Initial opinion matches satisfaction
    set initial-position opinion
    update-face-color

    ; Initially, satisfaction only considers non-social factors
    set satisfaction non-social-satisfaction

    ; Define initial behavior as predominantly neutral
    set behaviour ifelse-value (opinion < -0.2) ["oppo"] [
                  ifelse-value (opinion <= 0.2) ["neu"] ["suppo"]]
  ]

  behavior-evaluation   ; Evaluate behavior based on opinion

  ask individuals [
    ifelse show-labels?
      [ set label [who] of self
        set label-color black ]
      [ set label "" ]
  ]
end

to update-face-color    ; Update face color to represent opinions visually
  if opinion < -0.2 [ set color 105 + normalized-min-max opinion -1 0 0 4.5 ]
  if opinion > 0.2  [ set color 135 + normalized-min-max (1 - opinion) 0 1 0 4.5 ]
  if opinion > -0.2 and opinion < 0.2 [ set color 9 - normalized-min-max (abs opinion) 0 0.1 0 .5 ]
end

to update-alter-similarity  ; Assess similarity among connection neighbors
  let same-count count connection-neighbors with [behaviour = [behaviour] of myself]
  let total-count count connection-neighbors
  let %similarity ifelse-value (total-count > 0) [same-count / total-count] [0]
  set social-satisfaction normalized-min-max %similarity 0 1 -1 1
end

to behavior-evaluation   ; Evaluate behavior and adjust properties
  ask individuals [
    ;if ticks > 1 [
      set behaviour ifelse-value (opinion < -0.2) ["oppo"] [
                    ifelse-value (opinion <= 0.2) ["neu"] ["suppo"]]
   ; ]

    ; Update facial expression based on satisfaction
    set shape ifelse-value (satisfaction <= -0.2) ["face sad"] [
              ifelse-value (satisfaction <= 0.2) ["face neutral"] ["face happy"]]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;
;;; Go Procedures ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;
to go
  if ticks >= 10000 [ stop ]                ;; time for ending the voting process
  interact
  update-individuals
  update-networks
  evaluation
  tick
end

to interact
  ask individuals [
    let self-position opinion                     ; Current agent's opinion (self-position)
    let id-self [who] of self                     ; ID of the current agent
    let inter-neighbors connection-neighbors      ; Neighbors involved in the interaction
    calculate-distance-to-neighbors               ; Compute distances to connected neighbors

    ;; Iterate through interaction neighbors
    ask inter-neighbors [
      let id-neig [who] of self                   ; Neighbor's ID
      let advocated-position opinion              ; Neighbor's opinion (advocated position)
      let posit-distance (advocated-position - self-position)
      let posit-abs abs posit-distance            ; Absolute difference in opinions

      ;; Confirmation bias: Agents with confirmation bias are less influenced by differing opinions
      ;; and treat similar opinions as fully accepted, regardless of minor differences.
      if confirmation-bias? [
        set non-commitment 0                      ; Low emotion -> larger non-commitment
        set latitude-of-rejectance (latitude-of-acceptance + non-commitment)
        set posit-abs advocated-position * self-position
        ifelse posit-abs > 0                      ; Same opinions
          [set posit-abs 0]                       ; Acceptance when both positive or both negative
          [set posit-abs 2]                       ; Rejection for differing opinions
      ]

      ;; Assimilation (positive influence): Move closer if within acceptance latitude
      if posit-abs <= latitude-of-acceptance [
        set strength-variation 1                  ; Positive interaction -> move closer
        set self-position self-position + (posit-distance * conformity * reinforcement)
      ]

      ;; Neutral influence: No change in position
      if posit-abs > latitude-of-acceptance and posit-abs < latitude-of-rejectance [
        set strength-variation 0
      ]

      ;; Contrast (negative influence): Move further apart if beyond rejection latitude
      if posit-abs >= latitude-of-rejectance [
        set strength-variation -1                 ; Negative interaction -> move apart
        set self-position self-position - (posit-distance * conformity * reinforcement)
      ]

      ;; Bound the opinion between -1 and 1
      set self-position max (list -1 (min list self-position 1))

      ;; Move agents based on interaction outcome
      move-agents

      ;; Update connection strength for this interaction
      ask connection id-self id-neig [
        set link-strength link-strength + strength-variation
      ]
    ]

    ;; Update non-social satisfaction based on the new opinion
    set non-social-satisfaction self-position
  ]
end

to calculate-distance-to-neighbors
  let dist-list []                              ; Temporary list for storing distances
  ask connection-neighbors [
    let dist distance myself                    ; Calculate distance to this neighbor
    set dist-list lput dist dist-list           ; Add distance to the list
  ]
  set distance-neigh dist-list                  ; Store distances in the individual's variable
end

to move-agents
  let conne-length distance myself              ; Distance to the connection center

  ;; Adjust position based on interaction strength
  ask myself [
    let max-dis max distance-neigh              ; Maximum distance to neighbors
    if max-dis < 80 and conne-length < 50 and conne-length > 10 [
      face myself
      forward (0.05 * strength-variation)       ; Move based on interaction strength
    ]
  ]
end

to evaluation
  ;; Monitor the opinion of a specific individual
  let monitor-individual one-of individuals with [who = monitor-who]
  set who-opinion [opinion] of monitor-individual  ; Set the opinion of the monitored individual

  ;; Count the number of individuals with different opinion categories
  set oppo-value count individuals with [opinion < -0.1]       ; Negative opinions
  set neutral-value count individuals with [(opinion >= -0.1) and (opinion <= 0.1)]  ; Neutral opinions
  set suppo-value count individuals with [opinion > 0.1]       ; Positive opinions

  ;; Plot the opinion distribution
  plot-opinion-distribution
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;update;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to update-individuals
  ask individuals [
    let reconciliation (1 - level-of-involvement)  ; Measure of willingness to reconcile

    ;; Adjust latitude-of-acceptance based on reconciliation status
    ifelse reconcile? and reconciliation > 0 and not confirmation-bias?
      [ set latitude-of-acceptance (2 - 2 * level-of-involvement) ]
      [ set latitude-of-acceptance 1 ]

    ;; Update social attributes
    set social-importance conformity
    set non-commitment (1 - level-of-involvement)
    set latitude-of-rejectance (latitude-of-acceptance + non-commitment)

    ;; Update opinion and satisfaction
    set opinion non-social-satisfaction
    update-face-color
    update-alter-similarity

    ;; Calculate overall satisfaction
    set satisfaction (social-importance * social-satisfaction) + ((1 - social-importance) * non-social-satisfaction)
    behavior-evaluation
  ]
end

to update-networks
  ;; Reconciliation process: form new connections if the conditions are met
  let reconciliation 1 - level-of-involvement  ;; Calculate reconciliation factor

  ;; If reconciliation is enabled, reconciliation factor is positive, and no confirmation bias
  if reconcile? and reconciliation > 0 and not confirmation-bias? [
    while [count connections < 2 * reconciliation * avg-connections * num-agents / 2] [
      ask one-of individuals [
        let target min-one-of other individuals with [not connection-neighbor? myself] [distance myself]  ;; Find nearest individual without a connection
        if target != nobody [
          create-connection-with target  ;; Create a connection with the target
          ask connection [who] of self [who] of target [
            set color 8.5                 ;; Set initial connection color
            set link-strength 0           ;; Initialize link strength
          ]
        ]
      ]
    ]
  ]

  ;; Update network colors based on link strength
  ask individuals [
    ask connection-neighbors [
      ask connection [who] of myself [who] of self [
        ifelse link-strength > 0
          [ set color 8.5 / e ^ (0.01 * link-strength) ]   ;; Positive link strength: color based on exponential decay
          [ ifelse link-strength > -500
              [ set color 9 - 1 / e ^ (-0.01 * link-strength) ]  ;; Negative link strength but within range
              [ die ]  ;; Remove connections with very negative link strength
          ]
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;reporters ;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to-report random-normal-trunc [mid dev mmin mmax] ; Generate a truncated normal value within a specified range [mmin, mmax]
  let result random-normal mid dev
  while [result < mmin or result > mmax] [
    set result random-normal mid dev   ; Re-generate until within bounds
  ]
  report result
end

to-report normalized-min-max [norm-variable min-old max-old min-new max-new] ; Normalize the value of norm-variable from the old range [min-old, max-old] to the new range [min-new, max-new]
  let norm (min-new + (((norm-variable - min-old) * (max-new - min-new)) / (max-old - min-old)))
  report precision norm 4              ; Return the normalized value with 4 decimal places
end

to-report calculate-percentages [field-name] ; Calculate the percentage distribution of values in specified field (opinion or initial-position)
  let number-of-bins 20
  let bins n-values number-of-bins [0]       ; Initialize bins with zero values
  let min-opinion -1
  let max-opinion 1
  let bin-width 0.1

  ;; Distribute individuals' field values into bins
  ask individuals [
    let value ifelse-value (field-name = "opinion") [opinion] [initial-position]
    let bin-index floor ((value - min-opinion) / bin-width)
    set bin-index min (list max (list bin-index 0) (number-of-bins - 1))  ; Clamp bin index to valid range
    set bins replace-item bin-index bins (item bin-index bins + 1)
  ]

  let total count individuals                ; Total number of individuals
  report map [? -> (? / total) * 100] bins   ; Calculate percentage for each bin
end

to plot-opinion-distribution
  set-current-plot "%OPINION-DISTRIBUTION"
  clear-plot
  set-plot-x-range -1 1
  set-plot-y-range 0 80

  let bin-width 0.1
  let bin-centers (range -0.95 1.05 bin-width)

  ; Calculate percentages once, outside of ask individuals
  let current-percentages calculate-percentages "opinion"
  let initial-percentages calculate-percentages "initial-position"

  ; Plot the current percentages
  foreach bin-centers [bin-center ->
    let index position bin-center bin-centers
    if index >= 0 and index < length current-percentages [
      set percentage item index current-percentages
      set-current-plot-pen "Current"
      plotxy bin-center percentage
    ]
  ]

  ; Plot the initial percentages
  foreach bin-centers [bin-center ->
    let index position bin-center bin-centers
    if index >= 0 and index < length initial-percentages [
      set initial-percentage item index initial-percentages
      set-current-plot-pen "Initial"
      plotxy bin-center initial-percentage
    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
302
24
913
636
-1
-1
3.0
1
12
1
1
1
0
0
0
1
0
200
0
200
1
1
1
ticks
60.0

BUTTON
46
542
188
575
GO ONCE
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
46
586
189
619
GO
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
46
65
214
98
num-agents
num-agents
0
300
100.0
10
1
NIL
HORIZONTAL

BUTTON
46
499
188
532
SETUP
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

PLOT
926
286
1284
457
SUPPORTERS, NEUTRAL or OPPONENTS?
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Opponents" 1.0 0 -14070903 true "" "plot oppo-value"
"Supporters" 1.0 0 -955883 true "" "plot suppo-value"
"Neutral" 1.0 0 -5987164 true "" "plot neutral-value"

SWITCH
932
42
1082
75
show-labels?
show-labels?
1
1
-1000

TEXTBOX
931
20
1122
38
COMMUNITY FEATURE:
14
14.0
1

TEXTBOX
932
239
1082
257
SIMULATION RESULT:
14
14.0
1

PLOT
926
464
1286
633
%OPINION-DISTRIBUTION
0
NIL
-1.0
1.0
0.0
50.0
false
true
"" ""
PENS
"Initial" 0.1 0 -7500403 true "" ""
"Current" 0.1 1 -2674135 true "" ""

SLIDER
44
326
218
359
conformity
conformity
0
1
0.6
0.1
1
NIL
HORIZONTAL

SLIDER
44
387
218
420
level-of-involvement
level-of-involvement
0
1
0.4
0.1
1
NIL
HORIZONTAL

SWITCH
933
82
1082
115
show-links?
show-links?
0
1
-1000

PLOT
925
127
1282
280
individual-opinion-who 
NIL
0
0.0
10.0
-1.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot who-opinion"

INPUTBOX
1102
42
1193
102
monitor-who
0.0
1
0
Number

SLIDER
46
104
214
137
avg-connections
avg-connections
0
10
5.0
1
1
NIL
HORIZONTAL

SWITCH
45
199
216
232
confirmation-bias?
confirmation-bias?
1
1
-1000

TEXTBOX
48
38
240
56
Setting the community:
15
14.0
1

TEXTBOX
46
172
230
190
Setting the individuals:
15
14.0
1

TEXTBOX
45
473
195
492
Running the model:
15
14.0
1

TEXTBOX
46
424
222
442
Low <-- Moderate --> High
12
0.0
1

TEXTBOX
44
247
245
323
Individual traits: both \"conformity\" and \"involvement\" reflect the group average, ranging from low (left) to high (right).\n
12
0.0
1

TEXTBOX
46
362
216
380
Low <-- Moderate --> High
12
0.0
1

@#$#@#$#@
## WHAT IS IT?
This model demonstrates how opinions within a community change over time. Individuals' decisions are influenced by two main factors: personal needs (such as experiences and values) and social influences (Antosz et al., 2019). At the outset, each person's opinion is largely shaped by their personal needs. However, as they engage with others in the community, their opinions evolve through these social interactions.

## HOW IT WORKS
Opinions are visually represented by different facial colors:

* Blue face: Opposing opinions.
* Pink face: Supporting opinions.
* Gray face: Neutral opinions.

An individual’s opinion—whether neutral, opposing, or supporting—is determined through a calculation that accounts for both personal needs and social interaction experiences. Personal needs encompass an individual’s daily experiences and core beliefs, while social interactions reflect the experiences of agreeing or disagreeing with others. The overall satisfaction with a given proposal is shaped by the combination of personal satisfaction (based on individual needs) and social satisfaction (derived from social interactions), with the relative importance of each satisfaction influencing the outcome. Initially, the satisfaction of personal needs follows a normal distribution.

As individuals engage with their neighbors, their opinions may evolve through these interactions, aligning with or diverging from the opinions of others. This aligns with the principles of social judgment theory (Jager & Frédéric, 2004). Furthermore, the presence of "confirmation bias" (Li & Jager) plays a critical role in how individuals selectively process and interpret information within their social networks, reinforcing existing beliefs and influencing opinion dynamics.


## HOW TO USE IT
To use the model, you first need to set up the community, which determines the community context, and then set up the individuals, which defines their characteristics.

**Setting the community**

* **"num-agents"** parameter allows you to specify the number of agents within the community.

* **"avg-connections"**  represents the average number of connections (or links) that individuals establish with other agents. The influence of norms and the level of individual social satisfaction heavily depend on these connections. By default, agents are initially set to have five connections. It’s important to understand that this average does not mean every agent will have exactly five connections—some may have more, while others may have fewer. You can adjust this average number of connections using a slider, with a range from 0 to 10. 

**Setting the individual**

* **"confirmation-bias?"** This switch determines whether individuals exhibit confirmation bias. When enabled, confirmation bias is active, meaning individuals will only interact with others who share their opinions. When disabled, there is no confirmation bias, and individuals are open to engaging with others who may have differing opinions.

* **"conformity"** This parameter determines how much social influence affects an individual’s decision-making and overall satisfaction, with values ranging from 0 to 1. A value of 0.0 means that an individual’s satisfaction is entirely based on personal needs, without any influence from others. A value of 1.0 means that satisfaction is completely shaped by social interactions. Values between 0.0 and 1.0 represent a balance, where individuals consider both their personal needs and the opinions of others when forming their views and making decisions in social interactions.

* **"level-of-involvement"** This parameter represents the ego-involvement of individuals. Higher levels of "level-of-involvement" can narrow the latitude of acceptance and the non-commitment range, affecting how strongly individuals hold their opinions.

**Running the model**

* **"SETUP"** command is employed to configure the entire system.

* **"GO ONCE"** enables the model to execute for a single time step.

* **"GO"** function triggers ongoing execution of the model, enabling the generation of progress and outcomes based on the specified configurations.


### SYSTEM OUTPUT OVERVIEW
On the right side of the interface:

#### COMMUNITY FEATURE
* **"show-links?"** When this switch is on, the links between agents become visible, displaying the community structure. When off, the links remain hidden.

* **"show-labels?"** Turning this switch on makes the group ID visible. When off, the group ID is hidden. It should be switched on when monitoring a particular individual.

* **"monitor-who"** This input field (agent id) allows you to specify the agent you wish to monitor. When using this feature, the "show-labels" switch must be turned on to view the monitored agent's details.


#### SIMULATION RESULTS

* The **"individual-opinion-who"** Displays the dynamic evolution of a particular individual's opinion, as specified in the "monitor-who" input box.

* The **"SUPPORTERS or OPPONENTS?"** This chart displays the distribution of agents' opinions. "Opposing" refers to agents with opposing opinions, "Supporters" represents agents with supporting opinions, and "Neutral" indicates those with neutral opinions.

* The **"%OPINION-DISTRIBUTION"** illustrates the evolving opinions within the community. The "initial" display presents the original distribution of opinions as a histogram reflecting the percentage, while the "current" display shows the community's opinions in real-time.

## THINGS TO NOTICE

It is important to maintain static parameters for the community during model execution; changes to these parameters should be avoided. However, individual parameters can be adjusted while the model is running.

As the model operates, the connections between individuals become more apparent. Stronger connections indicate a higher frequency of positive interactions (acceptance), while weaker connections suggest a decline in interaction frequency (rejection).

Additionally, individuals may move closer to or further away from each other during the simulation. If an individual accepts the opinion of a connected neighbor, they move closer to that neighbor. If they reject the opinion, they move further away. If they neither accept nor reject, remaining non-committal, the individual stays in place without moving.


## THINGS TO TRY

### EXPERIMENT 1: Effect of Social Influence on Opinion Dynamics

**Objective**: To understand how varying levels of social influence (the "conformity" parameter) affect the evolution of opinions within the community.

**Setup**: Use the following settings in the interface:

- **`num-agents = 100`**
- **`avg-connections = 5`**
- **`level-of-involvement = 0.5`**
- **`confirmation-bias? = off`**
- **`conformity = 0.0`** 

Keep the control variables—"num-agents", "avg-connections", "level-of-involvement" and "confirmation-bias"—unchanged throughout the experiment. Vary the "conformity" parameter across a range from 0 (no social influence) to 1 (maximum social influence), representing low, moderate, and high levels of social impact.

For each level of "conformity", run the model to analyze how opinions evolve over time. Focus on the key outputs displayed on the right side of the interface: 1) The total number of supporters, opponents, and neutral individuals. 2)The distribution of opinions within the community.

Observe and compare the results across different levels of "conformity". As the parameter increases, note the changes in how strongly social interactions influence opinion formation and the resulting shifts in the overall distribution of opinions.


### EXPERIMENT 2: Impact of Confirmation Bias on Opinion Formation

**Objective**: To investigate how the presence of confirmation bias affects opinion convergence and polarization.

**Setup**: Use the following settings in the interface:

- **`num-agents = 100`**
- **`avg-connections = 5`**
- **`level-of-involvement = 0.5`**
- **`conformity = 0.5`**
- **`confirmation-bias? = off`** 

Set up the community with a default number of agents and average connections. Conduct two simulations: 1) With "confirmation-bias?" enabled. 2) With "confirmation-bias?" disabled. Keep all other variables constant, including "num-agents", "avg-connections", "conformity" and "level-of-involvement."

For each simulation, monitor: 1) The number of supporters, opponents, and neutral agents over time. 2) The distribution of individual opinions within the community.

Through observations, you can see, when confirmation bias is active, agents will primarily engage with others who share similar viewpoints. This selective interaction reinforces existing opinions, often amplifying polarization and reducing consensus.

In contrast, disabling confirmation bias allows agents to consider a broader range of perspectives, including opposing views. This leads to a more diverse exchange of ideas and promotes convergence and consensus within the community over time.

 
### EXPERIMENT 3: Role of Community Structure (Number of Connections) on Opinion Spread

**Objective**: To explore how the number of social connections (avg-connections) affects the spread of opinions and the formation of consensus or division.

**Setup**: Use the following settings in the interface:

- **`num-agents = 100`**
- **`level-of-involvement = 0.5`**
- **`conformity = 0.5`**
- **`confirmation-bias? = off`** 
- **`avg-connections = 1`**

Set up the community with a default number of agents. Run the model for different values of "avg-connections" (e.g., 1, 3, 5, 8). Observe the effect on the spread of opinions, as well as the distribution of opinions (supporters, opponents, neutral). Observe how social satisfaction (smiling faces) changes as the number of connections increases.

Observations show that with fewer connections, collective opinion formation is slower, as individuals tend to hold on to their original attitudes and remain more isolated. However, as the number of connections increases, opinions spread more rapidly, potentially leading to greater consensus and a more homogenized perspective across the community.

### EXPERIMENT 4: Impact of Personal Involvement on Opinion Flexibility

**Objective**: To examine how the "level-of-involvement" parameter, which reflects ego-involvement, influences the flexibility of individuals’ opinions.

**Setup**: Use the following settings in the interface:

- **`num-agents = 100`**
- **`conformity = 0.5`**
- **`confirmation-bias? = off`** 
- **`avg-connections = 5`**
- **`level-of-involvement = 0`**

Set up the community using default values for the number of agents and connections.
Run the model with varying levels of "level-of-involvement" (e.g., 0.0, 0.5, 1.0).
Monitor opinion shifts over time, the distribution of opinions, and overall satisfaction (smiling faces).

Through the experiments, it becomes clear that at lower levels of involvement, individuals are more receptive to social influence, allowing for greater flexibility in opinion formation. At higher levels of involvement, individuals become less tolerant of opposing views, leading to stronger opinion stability and increased polarization.


### EXPERIMENT 5: Combined Effect 

Beyond the above experiemnts, we can also explore the Combined Effect, such as the combined effect of **Social Influence** and  **Confirmation Bias**.

**Objective**: To explore how the combination of social influence (conformity) and confirmation bias affects opinion polarization and social satisfaction.

**Setup**: Configure the community with default values for agents, connections, and other parameters. Run the model for four combinations of conformity and confirmation bias settings:

- **`Conformity = 0.0, Confirmation Bias = off`**
- **`Conformity = 1.0, Confirmation Bias = off`**
- **`Conformity = 0.0, Confirmation Bias = on`**
- **`Conformity = 1.0, Confirmation Bias = on`**

Track the final opinion distribution and social satisfaction for each combination. 

High conformity combined with confirmation bias will quickly lead to the most polarized outcomes. In contrast, high conformity without confirmation bias may still result in opinion convergence, but with less extreme polarization compared to when confirmation bias is present.


### EXPERIMENT 6: Tracking a Specific Agent 

By varying key parameters such as conformity, confirmation bias, and community structure, we can better understand how these factors influence consensus or polarization, providing valuable insights for modeling social behaviors in real-world scenarios.

This model includes a function to track the opinion of a specific agent. To enable this, turn on the  **"show-labels"** option when setting up the model. Then, select an agent by entering its  **ID** into the  **"monitor-who"** input box.

Run the model using the settings from the previous five experiments, and track the selected agent’s opinion through the  **"individual-opinion-who"** chart.

Observe the evolution of this agent’s opinion and analyze the factors that may contribute to the observed changes.


## NETLOGO FEATURES

In this conceptual framework, the visual elements are organized according to a symbolic structure:

* **nodes or heads** represent individual agents.

* **connecting lines or edges** illustrate the relationships between these agents. 

* **colour of their faces**, can be bluish, grayish or pinkish. The intensity of the face color reflects the strength of the agent's opinion. For example, an agent with a opposing opinion will have a bluish face, with deeper shades of blue indicating stronger opposing opinions. Conversely, an agent with a supporting opinion will have a pinkish face, with more intense pink shades representing stronger positive opinions. Agents with neutral opinions will have a grayish face.

* **Facial expressions**, depicted as happy, sad, or neutral faces, depict the satisfaction, dissatisfaction, or neutrality experienced by the agents.

## CREDITS AND REFERENCES

* Antosz P, Jager W, Polhill G, Salt D, Alonso-Betanzos A, Sánchez-Maroño N, Guijarro-Berdiñas B, Rodríguez A. Simulation model implementing different relevant layers of social innovation, human choice behaviour and habitual structures. SMARTEES Deliverable. 2019.

* Jager, Wander, and Frédéric Amblard. "A dynamical perspective on attitude change." NAACSOS (North American Association for Computational Social and Organizational Science) Conference, Pittsburgh. 2004.

* Li, Teng, and Wander Jager. "How Availability Heuristic, Confirmation Bias and Fear May Drive Societal Polarisation: An Opinion Dynamics Simulation of the Case of COVID-19 Vaccination." Journal of Artificial Societies and Social Simulation 26.4 (2023): 2.

## COPYRIGHT AND LICENSE
This model was created by Shaoni Wang as part of the project ActIPLEx: Action for Interactive Anti-Polarisation Learning Experiences for a Better Democracy. ACTiSS was an EU Erasmus project aimed to combat social polarisation among young people by educating them about the dangers of polarisation and increasing their understanding of the mechanisms responsible for the process. 
Project number: 2023-2-PL01-KA220-HED-00017919.
More info: https://socialpolarisation.eu/.
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

neu-happy
false
3
Circle -6459832 true true 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -7500403 true false 150 15 45 120 255 120

neu-neutral
false
3
Circle -6459832 true true 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -7500403 true false 150 15 45 120 255 120

neu-sad
false
3
Circle -6459832 true true 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -7500403 true false 150 15 45 120 255 120

neutral 1
false
0
Circle -13791810 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

neutral 10
false
0
Circle -1184463 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

neutral 2
false
0
Circle -2064490 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

neutral 3
false
0
Circle -955883 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

neutral 4
false
0
Circle -11221820 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

neutral 5
false
0
Circle -14835848 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

neutral 6
false
0
Circle -13345367 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

neutral 7
false
0
Circle -8630108 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

neutral 8
false
0
Circle -13840069 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

neutral 9
false
0
Circle -6459832 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

oppo-happy
false
0
Circle -7500403 true true 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -13345367 true false 150 15 45 120 255 120

oppo-neutral
false
0
Circle -7500403 true true 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -13345367 true false 150 15 45 120 255 120

oppo-sad
false
0
Circle -7500403 true true 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -13345367 true false 150 15 45 120 255 120

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

sad 1
false
0
Circle -13791810 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -7500403 true true 150 15 45 120 255 120

sad 10
false
0
Circle -1184463 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -7500403 true true 150 15 45 120 255 120

sad 2
false
0
Circle -2064490 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -7500403 true true 150 15 45 120 255 120

sad 3
false
0
Circle -955883 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -7500403 true true 150 15 45 120 255 120

sad 4
false
0
Circle -11221820 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -7500403 true true 150 15 45 120 255 120

sad 5
false
0
Circle -14835848 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -7500403 true true 150 15 45 120 255 120

sad 6
false
0
Circle -13345367 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -7500403 true true 150 15 45 120 255 120

sad 7
false
0
Circle -8630108 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -7500403 true true 150 15 45 120 255 120

sad 8
false
0
Circle -13840069 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -7500403 true true 150 15 45 120 255 120

sad 9
false
0
Circle -6459832 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -7500403 true true 150 15 45 120 255 120

smile 1
false
0
Circle -13791810 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

smile 10
false
0
Circle -1184463 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

smile 2
false
0
Circle -2064490 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

smile 3
false
0
Circle -955883 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

smile 4
false
0
Circle -11221820 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

smile 5
false
0
Circle -14835848 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

smile 6
false
0
Circle -13345367 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

smile 7
false
0
Circle -8630108 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

smile 8
false
0
Circle -13840069 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

smile 9
false
0
Circle -6459832 true false 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -7500403 true true 150 15 45 120 255 120

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

suppo-happy
false
0
Circle -7500403 true true 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 255 105 240 90 225 90 225 90 210 90 203 120 225 150 240 192 218 210 203 210 210 210 225 210 225 195 240
Polygon -955883 true false 150 15 45 120 255 120

suppo-neutral
false
0
Circle -7500403 true true 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Rectangle -16777216 true false 105 225 195 240
Polygon -955883 true false 150 15 45 120 255 120

suppo-sad
false
0
Circle -7500403 true true 60 105 180
Circle -16777216 true false 105 150 30
Circle -16777216 true false 165 150 30
Polygon -16777216 true false 150 210 105 225 90 240 90 240 90 255 90 262 120 240 150 225 192 247 210 262 210 255 210 240 210 240 195 225
Polygon -955883 true false 150 15 45 120 255 120

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

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
set layout? false
set plot? false
setup repeat 300 [ go ]
repeat 100 [ layout ]
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="200"/>
    <metric>consistency</metric>
    <metric>A-supporters</metric>
    <metric>B-supporters</metric>
    <steppedValueSet variable="Normative-influence" first="0" step="0.1" last="1"/>
    <steppedValueSet variable="Conservertive-progressive" first="0" step="0.1" last="1"/>
  </experiment>
</experiments>
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

inter-groups
0.0
-0.2 0 0.0 1.0
0.0 1 4.0 4.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
