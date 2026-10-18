import subprocess,os,sys
CDB='/Applications/calibre.app/Contents/MacOS/calibredb'
LIB=os.path.abspath('TestLibrary'); os.makedirs('src',exist_ok=True)
B=[('Il nome della rosa','Umberto Eco','','Bompiani','Giallo,Medioevo,Classici','ita','Anno 1327: un frate francescano indaga su una serie di misteriosi delitti in un’abbazia benedettina.'),
('Il pendolo di Foucault','Umberto Eco','','Bompiani','Esoterismo,Romanzo','ita','Tre redattori inventano un Piano cosmico… che diventa reale.'),
('Se questo è un uomo','Primo Levi','','Einaudi','Memoir,Storia,Classici','ita','La testimonianza dell’esperienza ad Auschwitz.'),
('Il barone rampante','Italo Calvino','I nostri antenati','Einaudi','Classici,Romanzo','ita','Cosimo sale su un albero a dodici anni e decide di non scenderne più.'),
('Il visconte dimezzato','Italo Calvino','I nostri antenati','Einaudi','Classici,Fantastico','ita','Un visconte tagliato a metà da una palla di cannone.'),
('Il cavaliere inesistente','Italo Calvino','I nostri antenati','Einaudi','Classici,Fantastico','ita','Un’armatura vuota che esiste per pura forza di volontà.'),
('L’amica geniale','Elena Ferrante','L’amica geniale','E/O','Romanzo,Contemporanea','ita','Napoli, anni ’50: l’amicizia tra Lila ed Elena.'),
('Dune','Frank Herbert','Dune','Ace','Fantascienza,Classici','eng','The story of Paul Atreides on the desert planet Arrakis.'),
('Neuromancer','William Gibson','Sprawl','Ace','Fantascienza,Cyberpunk','eng','Case, a washed-up hacker, is hired for one last job.'),
('Foundation','Isaac Asimov','Foundation','Gnome Press','Fantascienza,Classici','eng','Hari Seldon and the science of psychohistory.'),
('Sapiens','Yuval Noah Harari','','Harper','Saggio,Storia','eng','A brief history of humankind.'),
('Il Gattopardo','Giuseppe Tomasi di Lampedusa','','Feltrinelli','Classici,Storico','ita','Se vogliamo che tutto rimanga com’è, bisogna che tutto cambi.'),
('Le città invisibili','Italo Calvino','','Einaudi','Classici,Fantastico','ita','Marco Polo descrive a Kublai Khan città impossibili.')]
POOL=['La notte scese sulla città e il mare restò immobile.','Un lungo viaggio attraverso il deserto cambiò la sua idea di libertà.','L’amicizia tra i due nacque tra i banchi di scuola.','Nell’abbazia, i monaci custodivano un segreto antico.','Il potere, scrisse, è una forma di memoria.','Dalla finestra si vedeva solo la pioggia e la strada vuota.']
subprocess.run([CDB,'--with-library',LIB,'list','-f','title'],capture_output=True)
for i,(t,a,s,p,tags,lang,c) in enumerate(B):
    f=f'src/{i+1:02d}.txt'
    open(f,'w').write(f'{t}\n{a}\n\n'+'\n\n'.join(f'Capitolo {k+1}\n\n'+' '.join(POOL[(i+k+j)%6] for j in range(8)) for k in range(5)))
    cmd=[CDB,'--with-library',LIB,'add','-t',t,'-a',a,'-T',tags,'-l',lang,'-d?'] 
    cmd=[CDB,'--with-library',LIB,'add','-t',t,'-a',a,'-T',tags,'-l',lang]
    if s: cmd+=['-s',s]
    r=subprocess.run(cmd+[f],capture_output=True,text=True); print(t,r.stdout.strip(),r.stderr.strip()[:100])
