// frequent english words the spell-corrector must leave alone (it only knows shopping vocabulary)
module.exports = new Set(`
able about above accept across act action actually add added address after afternoon again against age ago agree ahead air
all allow almost alone along already alright also although always amazing amount among and angry animal another answer any
anybody anymore anyone anything anyway anywhere appear apply appreciate area arm around arrive arrived arriving art article ask
asked asking assistant attention aunt available average avoid awake away awesome baby back bad badly balance bank base based
basic basket bath beat beautiful became because become bed been before began begin behind being believe below beside besides
between beyond big bigger bill bird birth bit bite black blame blind block blood blow board boat body book bored boring born
borrow boss both bother bottle bottom bought box boy brain brand bread break breakfast bring broke broken brother brought build
building burn bus business busy buy buyer buying cake call called calm came camera can cancel cannot capable capital car card
care career careful carry case cash catch cause cell center central certain certainly chance change changed changes channel
chat cheap check cheese chicken child choose chose city claim class classic clean clear clearly climb clock close closed cloth
club coach coat code coffee cold collect college come comes coming comment common company complete completely computer concern
condition confirm confirmed consider contact contain continue control cook cool copy corner correct cost could count country
couple course cover crazy create credit cross crowd cry cup current customer cut cute daily damage damaged dance danger dark
data date daughter day dead deal dear death decide decided decision deep definitely degree deliver delivered delivering delivery
depend describe design detail details develop device die diet difference different difficult dinner direct direction dirty
discover discuss dish dispatch dispatched distance do doctor does dog doing dollar done door double doubt down draw dream dress
drink drive drop dropped drops dry due during duty each early earn easily east easy eat edge effect effort either else email
empty end ended enemy energy enjoy enough enter entire especially even evening event ever every everybody everyone everything
exact exactly exam example excellent except exchange excited exciting excuse exercise exist exit expect experience explain
extra eye face fact fail fair fall false family famous fan fancy far farewell farm fast fat father fault favorite favourite fear
feature features feel feeling feet fell felt few field fight figure fill final finally find fine finger finish finished fire
firm fish fit fits fix flat floor fly follow food foot force forget forgot form forward found free fresh friend from front fruit
full fun funny future gain game garden gas gave general get gets getting girl give given glad glass goal going gone good got
government grab great green ground group grow guarantee guess guest guide guy hair half hall hand handle hang happen happened
happy hard hardly hate have head health hear heard heart heat heavy hello help helpful here hey hide high hill hire history hit
hold hole holiday home hope horse hospital hot hotel hour house however huge human hungry hurry hurt idea ideal ideas if ill
image imagine important improve include included including indeed inside instead interest interested interesting into issue
item job join joke journey judge juice jump just keep kept key kick kill kind king kitchen knew know knowledge known lady land
language large last late later laugh law lay lead learn least leave leaving left leg less lesson let letter level lie life lift
like likely limit line link list listen little live lived lives living load local lock long look looking lose loss lost lot
loud love lovely low luck lunch machine made mail main major make makes making man manage many mark market married match matter
maybe mean meaning means meant meet meeting member memory mention menu message met method middle might mile mind minister minute
miss missing mistake modern moment money month mood morning most mostly mother move movie much music must name nation natural
near nearly necessary neck need needed needs neither never next nice night nobody noise none normal north note nothing notice
now number nurse object obviously offer office often oil old once only open order ordered ordering other otherwise out outside
over own owner pack page paid pain paint pair paper parent park part party pass past path pay paying payment peace people per
perfect perhaps period person phone pick picked picture piece place plan plane plant play played player please pleased plus
pocket point police poor popular position possible post pound power practice prefer prepare present president pretty prevent
price priced prime print private probably problem process produce program promise proper protect proud prove provide public
pull purchase purchased purpose push put question quick quickly quiet quite race rain raise ran range rate rather reach read
ready real really reason receive received recent recently record red reduce refuse relax release remain remember remove rent
repair repeat reply report request rest result return rich ride right ring rise risk road rock role room round rule run rush
safe said sale same save saw say saying says school score screen sea search season seat second secret see seem seen sell send
sense sent serious serve service services set settle several shake shall shape share sharp shelf shine ship shirt shock shoot
shop shopping short shot should shout show shut sick side sign silly simple since sing single sir sister sit site size skill
skin sky sleep slow small smart smell smile smoke snow social soft sold some somebody someone something sometimes son song soon
sorry sort sound south space speak special spend spent spot spring staff stage stand standard star start state station stay
step stick still stock stop store story straight strange street stress strong student study stuff stupid style subject success
such sudden suggest suit summer sun super supply support suppose sure surprise sweet table take taken takes taking talk tall
taste teach teacher team tear tell term test text than thank thanks that their them then there these they thick thin thing
think third this those though thought through throw ticket tie till time tiny tip tips tired title today together told tomorrow
tonight too took top total touch tough tour toward town track tracking trade traffic train training travel treat tree trip
trouble true trust truth try trying turn twice type ugly uncle under understand unit until upon upset use used useful usual
usually value very view visit voice wait waiting wake walk wall want wanted war warm warn wash waste watch water way wear weather
week weekend weight welcome well went were west what whatever wheel when where whether which while white whole why wide wife
wild will win wind window winter wish within without woman wonder wonderful word work worked world worry worse worst worth would
write writing wrong yard yeah year yellow yes yesterday yet young your yourself zone python homework poem weather news married
zelora cartwise bored song dinner cook capital match feelings sleep human funny stupid dance sing music movie favourite costlier pricier fancier classier
`.split(/\s+/).filter(Boolean));
